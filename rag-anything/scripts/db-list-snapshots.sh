#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init snapshots
rf_load_env
rf_require_cmds date du find

if [ ! -d "$BACKUPS_DIR" ] || ! ls "$BACKUPS_DIR"/pgdump-*.sql.gz >/dev/null 2>&1; then
  rf_info "no snapshots in $BACKUPS_DIR"
  exit 0
fi

printf "%-40s %10s %20s\n" "FILE" "SIZE" "MODIFIED"
while IFS= read -r f; do
  printf "%-40s %10s %20s\n" \
    "$(basename "$f")" \
    "$(du -h "$f" | awk '{print $1}')" \
    "$(date -r "$f" "+%Y-%m-%d %H:%M:%S")"
done < <(find "$BACKUPS_DIR" -maxdepth 1 -name 'pgdump-*.sql.gz' -type f -print | sort -r)
