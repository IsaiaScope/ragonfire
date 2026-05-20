#!/usr/bin/env bash
# Create the ext4 loopback image on Crucial-4T (or wherever PGDATA_IMG points).
# Idempotent: bails cleanly if the image already exists unless --force.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init db-init

PGDATA_IMG_OVERRIDE="${PGDATA_IMG:-}"
PGDATA_IMG_CAP_OVERRIDE="${PGDATA_IMG_CAP:-}"
rf_load_env_or_example
[ -n "$PGDATA_IMG_OVERRIDE" ] && PGDATA_IMG="$PGDATA_IMG_OVERRIDE"
[ -n "$PGDATA_IMG_CAP_OVERRIDE" ] && PGDATA_IMG_CAP="$PGDATA_IMG_CAP_OVERRIDE"
rf_require_cmds docker truncate

: "${PGDATA_IMG:?PGDATA_IMG must be set in .env}"
: "${PGDATA_IMG_CAP:=50G}"

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ -f "$PGDATA_IMG" ] && [ "$FORCE" -eq 0 ]; then
  echo "[db-init] $PGDATA_IMG already exists. Use --force to recreate (DESTRUCTIVE)." >&2
  exit 0
fi

if [ "$FORCE" -eq 1 ] && [ -f "$PGDATA_IMG" ]; then
  rf_confirm_destructive "recreate-pgdata" "remove and recreate $PGDATA_IMG"
  rf_info "--force: removing existing image"
  rf_run rm -f "$PGDATA_IMG"
fi

rf_run mkdir -p "$(dirname "$PGDATA_IMG")"

rf_validate_size "$PGDATA_IMG_CAP"
rf_info "allocating $PGDATA_IMG_CAP at $PGDATA_IMG"
rf_run truncate -s "$PGDATA_IMG_CAP" "$PGDATA_IMG"

rf_info "formatting ext4 inside the image (via helper container)"
rf_run docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && mkfs.ext4 -F -L ragonfire-pgdata /img"

rf_info "done. Next: /lightrag-start"
