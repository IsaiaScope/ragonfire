#!/usr/bin/env bash
# Restore from a named or latest snapshot. Refuses if DB has user tables unless --force.
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init restore
rf_load_env
rf_require_runtime_env
rf_require_cmds docker find gzip gunzip

FORCE=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET=$(find "$BACKUPS_DIR" -maxdepth 1 -name 'pgdump-*.sql.gz' -type f -print 2>/dev/null | sort -r | head -1 || true)
  [ -n "$TARGET" ] || { echo "[restore] no snapshots in $BACKUPS_DIR" >&2; exit 1; }
fi
[ -f "$TARGET" ] || { echo "[restore] not found: $TARGET" >&2; exit 1; }
rf_info "checking gzip integrity: $TARGET"
rf_run gzip -t "$TARGET"

rf_info "checking postgres reachability"
rf_pg_query "SELECT 1" >/dev/null

if [ "$FORCE" -eq 0 ]; then
  USER_TABLES=$(rf_pg_query "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'lightrag%'")
  [ "$USER_TABLES" = "0" ] || { echo "[restore] DB has LightRAG tables. Re-run with --force to overwrite." >&2; exit 1; }
else
  rf_confirm_destructive "restore-pgdata" "restore $TARGET into database $POSTGRES_DATABASE"
fi

rf_info "stopping lightrag-server before restore if running"
rf_compose stop lightrag-server >/dev/null 2>&1 || true

rf_info "restoring $TARGET into $POSTGRES_DATABASE"
gunzip -c "$TARGET" | docker exec -i ragonfire-postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -v ON_ERROR_STOP=1

META_VERSION=$(rf_pg_query "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || true)
if [ -n "$META_VERSION" ]; then
  rf_info "restored lightrag_version=$META_VERSION"
else
  rf_warn "restore completed but lightrag_meta.lightrag_version was not found"
fi

rf_info "OK"
