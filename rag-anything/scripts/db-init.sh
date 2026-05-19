#!/usr/bin/env bash
# Create the ext4 loopback image on Crucial-4T (or wherever PGDATA_IMG points).
# Idempotent: bails cleanly if the image already exists unless --force.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$REPO_DIR/rag-anything/.env.example"
PGDATA_IMG_OVERRIDE="${PGDATA_IMG:-}"
PGDATA_IMG_CAP_OVERRIDE="${PGDATA_IMG_CAP:-}"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
[ -n "$PGDATA_IMG_OVERRIDE" ] && PGDATA_IMG="$PGDATA_IMG_OVERRIDE"
[ -n "$PGDATA_IMG_CAP_OVERRIDE" ] && PGDATA_IMG_CAP="$PGDATA_IMG_CAP_OVERRIDE"

: "${PGDATA_IMG:?PGDATA_IMG must be set in .env}"
: "${PGDATA_IMG_CAP:=50G}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -f "$PGDATA_IMG" ] && [ "$FORCE" -eq 0 ]; then
  echo "[db-init] $PGDATA_IMG already exists. Use --force to recreate (DESTRUCTIVE)." >&2
  exit 0
fi

if [ "$FORCE" -eq 1 ] && [ -f "$PGDATA_IMG" ]; then
  echo "[db-init] --force: removing existing image"
  rm -f "$PGDATA_IMG"
fi

mkdir -p "$(dirname "$PGDATA_IMG")"

echo "[db-init] allocating $PGDATA_IMG_CAP at $PGDATA_IMG"
truncate -s "$PGDATA_IMG_CAP" "$PGDATA_IMG"

echo "[db-init] formatting ext4 inside the image (via helper container)"
docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && mkfs.ext4 -F -L ragonfire-pgdata /img"

echo "[db-init] done. Next: /lightrag-start"
