#!/bin/sh
# Mount /mnt/host/pgdata.ext4.img as loopback ext4 onto /pgdata-vol
# and ensure the postgres user owns the data dir.
set -eu

IMG=/mnt/host/pgdata.ext4.img
MNT=/pgdata-vol
PGDATA="$MNT/pg"

[ -f "$IMG" ] || { echo "[pg-init] FATAL: $IMG missing - run db-init.sh first" >&2; exit 1; }

mkdir -p "$MNT"

if mountpoint -q "$MNT"; then
  echo "[pg-init] $MNT already mounted - reusing"
else
  echo "[pg-init] mounting $IMG -> $MNT"
  mount -o loop "$IMG" "$MNT"
fi

mkdir -p "$PGDATA"
chown -R 999:999 "$PGDATA"
chmod 700 "$PGDATA"
echo "[pg-init] OK"
