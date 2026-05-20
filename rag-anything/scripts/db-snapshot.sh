#!/usr/bin/env bash
# pg_dump | gzip > $BACKUPS_DIR/pgdump-YYYYMMDD-HHMMSS.sql.gz
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init snapshot
rf_load_env
rf_require_runtime_env
rf_require_cmds docker gzip

rf_run mkdir -p "$BACKUPS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUPS_DIR/pgdump-$TS.sql.gz"

rf_info "writing snapshot: $OUT"
docker exec ragonfire-postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" --format=plain \
  | gzip > "$OUT"

SIZE=$(du -h "$OUT" | awk '{print $1}')
rf_info "OK ($SIZE)"
