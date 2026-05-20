#!/usr/bin/env bash
# Stops the stack, grows the loopback image, resizes ext4, restarts.
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init db-grow

NEW_SIZE="${1:-}"
[ -n "$NEW_SIZE" ] || { echo "usage: db-grow.sh <new-size>  (e.g. 100G, 500G, 1T)" >&2; exit 1; }
rf_validate_size "$NEW_SIZE"

rf_load_env
rf_require_runtime_env
rf_require_cmds docker python3 truncate
rf_require_file "$PGDATA_IMG" "$PGDATA_IMG missing - run db-init.sh first"

current_bytes=$(python3 - "$PGDATA_IMG" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).stat().st_size)
PY
)
new_bytes=$(rf_size_bytes "$NEW_SIZE")
[ "$new_bytes" -gt "$current_bytes" ] || rf_die "new size $NEW_SIZE is not larger than current image size $current_bytes bytes"
rf_confirm_destructive "grow-pgdata" "stop stack and resize $PGDATA_IMG to $NEW_SIZE"

# resize2fs/truncate mutate the filesystem in place; an interrupted resize can
# corrupt it. Take a snapshot first while the DB is still up and reachable.
if docker ps --format '{{.Names}}' | grep -q '^ragonfire-postgres$'; then
  rf_info "taking pre-grow snapshot"
  "$SCRIPT_DIR/db-snapshot.sh"
else
  rf_warn "postgres not running; skipping pre-grow snapshot (no live DB to dump)"
fi

rf_info "stopping stack"
"$SCRIPT_DIR/lightrag-stop.sh"

rf_info "extending file to $NEW_SIZE"
rf_run truncate -s "$NEW_SIZE" "$PGDATA_IMG"

rf_info "fsck + resize2fs (inside helper container)"
MSYS_NO_PATHCONV=1 rf_run docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
  "apk add --no-cache --quiet e2fsprogs >/dev/null && e2fsck -f -y /img && resize2fs /img"

rf_info "restarting"
"$SCRIPT_DIR/lightrag-start.sh"

rf_info "OK"
