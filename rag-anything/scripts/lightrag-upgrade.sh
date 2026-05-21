#!/usr/bin/env bash
# Snapshot the DB, wipe + recreate the .img, re-ingest every file in INPUT_DIR,
# then assert the new lightrag-hku pin got stamped (lightrag-start does the
# stamping on the fresh DB; this script verifies it). Only files in INPUT_DIR
# survive the wipe; the pre-upgrade snapshot is the recovery point.
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_bootstrap upgrade
rf_require_cmds find gzip grep sed

NEW_VERSION=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
[ -n "$NEW_VERSION" ] || { echo "[upgrade] cannot read pinned version from requirements.txt" >&2; exit 1; }
shopt -s nullglob
INPUT_FILES=("$INPUT_DIR"/*)
if [ ${#INPUT_FILES[@]} -eq 0 ]; then
  rf_warn "$INPUT_DIR has no files; upgrade will recreate an empty knowledge base"
fi
rf_warn "upgrade ONLY re-ingests files in $INPUT_DIR."
rf_warn "documents ingested from any other path are NOT recovered after the wipe."
rf_warn "ensure every source document lives in $INPUT_DIR before continuing."
rf_confirm_destructive "upgrade-lightrag" "snapshot, wipe $PGDATA_IMG, recreate it, and re-ingest every file in $INPUT_DIR"
# One confirmation authorizes the whole cascade; child scripts must not re-prompt.
export RAGONFIRE_ASSUME_YES=1
rf_info "target lightrag-hku == $NEW_VERSION"

rf_info "taking pre-upgrade snapshot"
"$SCRIPT_DIR/db-snapshot.sh"
SNAPSHOT=$(rf_latest_snapshot)
rf_verify_snapshot "$SNAPSHOT"

rf_info "stopping stack"
"$SCRIPT_DIR/lightrag-stop.sh"

# Once the .img is wiped the old data lives only in $SNAPSHOT. Any failure
# before the fresh stack is up restores it. (lightrag-start will then report a
# schema mismatch until the pin is reverted or upgrade re-run — that is
# expected: old data, new code.)
rollback() {
  trap - ERR
  rf_warn "upgrade aborted after wipe; restoring pre-upgrade snapshot $SNAPSHOT"
  "$SCRIPT_DIR/db-restore.sh" --force "$SNAPSHOT" \
    || rf_warn "rollback restore FAILED; recover manually: db-restore.sh --force $SNAPSHOT"
  rf_die "upgrade failed and was rolled back to the pre-upgrade snapshot"
}
trap rollback ERR

rf_info "wiping .img"
"$SCRIPT_DIR/db-init.sh" --force

rf_info "starting stack on fresh DB"
"$SCRIPT_DIR/lightrag-start.sh"

trap - ERR

# Re-ingest is best-effort: a single bad file must not abort the whole upgrade
# and strand a half-built KB. Tally failures and keep the snapshot for recovery.
rf_info "re-ingesting $INPUT_DIR"
INGESTED=0
FAILED=()
for f in "$INPUT_DIR"/*; do
  [ -f "$f" ] || continue
  rf_info "ingest: $f"
  if "$RUNTIME_DIR/.venv/bin/python" "$SCRIPT_DIR/ingest.py" "$f"; then
    INGESTED=$((INGESTED + 1))
  else
    rf_warn "ingest FAILED: $f"
    FAILED+=("$f")
  fi
done
if [ "$INGESTED" -eq 0 ]; then
  rf_warn "no files were re-ingested from $INPUT_DIR"
fi

# lightrag-start stamps the pin on a fresh DB; assert it actually happened so a
# refactor of that side effect cannot let an unstamped DB pass silently.
STAMPED=$(rf_pg_query "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || true)
[ "$STAMPED" = "$NEW_VERSION" ] \
  || rf_die "version stamp mismatch after upgrade: stamped='$STAMPED' expected='$NEW_VERSION' (snapshot kept: $SNAPSHOT)"

if [ "${#FAILED[@]}" -gt 0 ]; then
  rf_warn "re-ingest finished with ${#FAILED[@]} failure(s):"
  for f in "${FAILED[@]}"; do rf_warn "  - $f"; done
  rf_warn "pre-upgrade snapshot retained: $SNAPSHOT"
  rf_warn "fix the file(s) and re-ingest, or revert: db-restore.sh --force $SNAPSHOT"
  exit 1
fi

rf_info "OK (lightrag_version=$NEW_VERSION, reingested=$INGESTED)"
