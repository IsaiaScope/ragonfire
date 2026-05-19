#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

if [ ! -d "$BACKUPS_DIR" ] || ! ls "$BACKUPS_DIR"/pgdump-*.sql.gz >/dev/null 2>&1; then
  echo "(no snapshots in $BACKUPS_DIR)"
  exit 0
fi

printf "%-40s %10s %20s\n" "FILE" "SIZE" "MODIFIED"
for f in $(ls -1t "$BACKUPS_DIR"/pgdump-*.sql.gz); do
  printf "%-40s %10s %20s\n" \
    "$(basename "$f")" \
    "$(du -h "$f" | awk '{print $1}')" \
    "$(date -r "$f" "+%Y-%m-%d %H:%M:%S")"
done
