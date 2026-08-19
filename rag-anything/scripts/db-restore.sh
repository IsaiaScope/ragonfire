#!/usr/bin/env bash
# Restore from a named or latest snapshot. Refuses if DB has user tables unless --force.
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_bootstrap restore
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

# The snapshot is a self-contained plain dump: it recreates ag_catalog, the AGE
# extension, the graph schema and every lightrag_* table with no IF NOT EXISTS
# guards. The live DB was pre-seeded by init.sql (AGE + vector), so a replay
# collides on the first CREATE (ON_ERROR_STOP aborts). Reset to an empty DB
# first so the dump is authoritative. Only under --force (drops all data).
if [ "$FORCE" -eq 1 ]; then
  rf_info "resetting target DB before replay (--force)"
  rf_pg_psql_stdin <<'SQL'
DROP SCHEMA IF EXISTS chunk_entity_relation CASCADE;
DROP EXTENSION IF EXISTS age CASCADE;
DROP SCHEMA IF EXISTS ag_catalog CASCADE;
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
SQL
fi

rf_info "restoring $TARGET into $POSTGRES_DATABASE"
gunzip -c "$TARGET" | rf_pg_psql_stdin

META_VERSION=$(rf_pg_query "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || true)
if [ -n "$META_VERSION" ]; then
  rf_info "restored lightrag_version=$META_VERSION"
else
  rf_warn "restore completed but lightrag_meta.lightrag_version was not found"
fi

rf_info "OK"
