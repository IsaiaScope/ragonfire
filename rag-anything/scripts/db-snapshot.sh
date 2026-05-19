#!/usr/bin/env bash
# pg_dump | gzip > $BACKUPS_DIR/pgdump-YYYYMMDD-HHMMSS.sql.gz
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a

mkdir -p "$BACKUPS_DIR"
TS=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUPS_DIR/pgdump-$TS.sql.gz"

echo "[snapshot] -> $OUT"
docker exec ragonfire-postgres \
  pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" --format=plain \
  | gzip > "$OUT"

SIZE=$(du -h "$OUT" | awk '{print $1}')
echo "[snapshot] OK ($SIZE)"
