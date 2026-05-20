#!/bin/bash
# Loop-mount /mnt/host/pgdata.ext4.img onto /pgdata-vol so Postgres data lives
# inside the ext4 image (portable across hosts via the bind-mounted .img file).
# Then hand off to the official postgres entrypoint.
set -e

IMG=/mnt/host/pgdata.ext4.img
MNT=/pgdata-vol
PGDATA_DIR="$MNT/pg"

[ -f "$IMG" ] || { echo "[pg] FATAL: $IMG missing (run db-init.sh on host first)" >&2; exit 1; }

mkdir -p "$MNT"

if mountpoint -q "$MNT"; then
  echo "[pg] $MNT already mounted - reusing"
else
  echo "[pg] mounting $IMG -> $MNT (ext4 loopback)"
  mount -o loop "$IMG" "$MNT"
fi

mkdir -p "$PGDATA_DIR"
chown -R postgres:postgres "$PGDATA_DIR"
chmod 700 "$PGDATA_DIR"

# Hand off to the official postgres entrypoint, which handles user-switching itself.
exec docker-entrypoint.sh "$@"
