#!/usr/bin/env bash
# Snapshots, wipes .img, re-inits, re-ingests everything in INPUT_DIR,
# then bumps lightrag_meta.lightrag_version to the new pin.
set -euo pipefail
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a
REPO_DIR="${RAGONFIRE_REPO_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )}"

NEW_VERSION=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
[ -n "$NEW_VERSION" ] || { echo "[upgrade] cannot read pinned version from requirements.txt" >&2; exit 1; }
echo "[upgrade] target lightrag-hku == $NEW_VERSION"

echo "[upgrade] taking pre-upgrade snapshot"
"$REPO_DIR/rag-anything/scripts/db-snapshot.sh"

echo "[upgrade] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[upgrade] wiping .img (DESTRUCTIVE)"
"$REPO_DIR/rag-anything/scripts/db-init.sh" --force

echo "[upgrade] starting stack on fresh DB"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[upgrade] re-ingesting $INPUT_DIR"
shopt -s nullglob
for f in "$INPUT_DIR"/*; do
  [ -f "$f" ] || continue
  echo "[upgrade]   $f"
  "$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/scripts/ingest.py" "$f"
done

echo "[upgrade] OK (lightrag_version=$NEW_VERSION)"
