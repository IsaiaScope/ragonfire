#!/usr/bin/env bash
# Restore from a named or latest snapshot. Refuses if DB has user tables unless --force.
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

FORCE=0
TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    *) TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET=$(ls -1t "$BACKUPS_DIR"/pgdump-*.sql.gz 2>/dev/null | head -1)
  [ -n "$TARGET" ] || { echo "[restore] no snapshots in $BACKUPS_DIR" >&2; exit 1; }
fi
[ -f "$TARGET" ] || { echo "[restore] not found: $TARGET" >&2; exit 1; }

if [ "$FORCE" -eq 0 ]; then
  USER_TABLES=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'lightrag%'")
  [ "$USER_TABLES" = "0" ] || { echo "[restore] DB has LightRAG tables. Re-run with --force to overwrite." >&2; exit 1; }
fi

echo "[restore] <- $TARGET"
gunzip -c "$TARGET" | docker exec -i ragonfire-postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -v ON_ERROR_STOP=1

echo "[restore] OK"
