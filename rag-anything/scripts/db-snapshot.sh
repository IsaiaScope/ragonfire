#!/usr/bin/env bash
# pg_dump | gzip > $BACKUPS_DIR/pgdump-YYYYMMDD-HHMMSS.sql.gz
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_bootstrap snapshot
rf_require_cmds docker gzip

rf_run mkdir -p "$BACKUPS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUPS_DIR/pgdump-$TS.sql.gz"

rf_info "writing snapshot: $OUT"
rf_pg_dump | gzip > "$OUT"

SIZE=$(du -h "$OUT" | awk '{print $1}')
rf_info "OK ($SIZE)"
