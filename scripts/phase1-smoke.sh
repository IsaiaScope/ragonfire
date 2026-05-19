#!/usr/bin/env bash
# Brings the stack up against a throwaway .img and verifies extensions load.
set -euo pipefail
export COPYFILE_DISABLE=1

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMP_IMG=$(mktemp -d)/pgdata.ext4.img
TMP_ENV=$(mktemp)
trap 'LIGHTRAG_ENV_FILE="$TMP_ENV" docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$TMP_ENV" down -v 2>/dev/null || true; rm -rf "$(dirname "$TMP_IMG")" "$TMP_ENV"' EXIT

cp "$REPO_DIR/rag-anything/.env.example" "$TMP_ENV"
sed -i.bak "s|^PGDATA_IMG=.*|PGDATA_IMG=$TMP_IMG|" "$TMP_ENV"
sed -i.bak "s|^PGDATA_IMG_CAP=.*|PGDATA_IMG_CAP=200M|" "$TMP_ENV"
rm -f "${TMP_ENV}.bak"

PGDATA_IMG="$TMP_IMG" PGDATA_IMG_CAP=200M RAGONFIRE_RUNTIME="$(dirname "$TMP_IMG")" \
  "$REPO_DIR/rag-anything/scripts/db-init.sh"

find "$REPO_DIR/infra" -name '._*' -delete
LIGHTRAG_ENV_FILE="$TMP_ENV" docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$TMP_ENV" up -d --build pg-init postgres
echo "[smoke] waiting for postgres health..."
for _ in $(seq 1 30); do
  health=$(docker inspect --format '{{.State.Health.Status}}' ragonfire-postgres 2>/dev/null || echo "starting")
  [ "$health" = "healthy" ] && break
  sleep 2
done
[ "$health" = "healthy" ] || { echo "[smoke] postgres never became healthy"; exit 1; }

docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "\dx" | grep -q vector
docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "\dx" | grep -q age
docker exec ragonfire-postgres psql -U ragonfire -d ragonfire -c "SELECT key FROM lightrag_meta;"

echo "[smoke] PASS"
