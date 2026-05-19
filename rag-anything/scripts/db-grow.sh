#!/usr/bin/env bash
# Stops the stack, grows the loopback image, resizes ext4, restarts.
set -euo pipefail
NEW_SIZE="${1:-}"
[ -n "$NEW_SIZE" ] || { echo "usage: db-grow.sh <new-size>  (e.g. 100G, 500G, 1T)" >&2; exit 1; }

# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a
REPO_DIR="${RAGONFIRE_REPO_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )}"

echo "[grow] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[grow] extending file to $NEW_SIZE"
truncate -s "$NEW_SIZE" "$PGDATA_IMG"

echo "[grow] fsck + resize2fs (inside helper container)"
docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && e2fsck -f -y /img && resize2fs /img"

echo "[grow] restarting"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[grow] OK"
