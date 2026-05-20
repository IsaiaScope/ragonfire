#!/usr/bin/env bash
# Snapshots, wipes .img, re-inits, re-ingests everything in INPUT_DIR,
# then bumps lightrag_meta.lightrag_version to the new pin.
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init upgrade
rf_load_env
rf_require_runtime_env
rf_require_cmds grep sed

NEW_VERSION=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
[ -n "$NEW_VERSION" ] || { echo "[upgrade] cannot read pinned version from requirements.txt" >&2; exit 1; }
rf_confirm_destructive "upgrade-lightrag" "snapshot, wipe $PGDATA_IMG, recreate it, and re-ingest every file in $INPUT_DIR"
export RAGONFIRE_ASSUME_YES=1
rf_info "target lightrag-hku == $NEW_VERSION"

rf_info "taking pre-upgrade snapshot"
"$REPO_DIR/rag-anything/scripts/db-snapshot.sh"

rf_info "stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

rf_info "wiping .img"
"$REPO_DIR/rag-anything/scripts/db-init.sh" --force

rf_info "starting stack on fresh DB"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

rf_info "re-ingesting $INPUT_DIR"
shopt -s nullglob
for f in "$INPUT_DIR"/*; do
  [ -f "$f" ] || continue
  rf_info "ingest: $f"
  "$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/scripts/ingest.py" "$f"
done

rf_info "OK (lightrag_version=$NEW_VERSION)"
