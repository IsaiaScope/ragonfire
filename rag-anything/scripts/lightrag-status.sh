#!/usr/bin/env bash
# Quick health snapshot of the whole stack.
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
ENV_FILE="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"
[ -f "$ENV_FILE" ] || { echo "[status] no .env"; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

echo "=== Ollama ==="
pgrep -x ollama >/dev/null && echo "daemon: running" || echo "daemon: STOPPED"
curl -sf http://localhost:11434/api/tags >/dev/null && echo "api: 200" || echo "api: DOWN"

echo
echo "=== Docker ==="
LIGHTRAG_ENV_FILE="$ENV_FILE" docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$ENV_FILE" ps

echo
echo "=== Postgres ==="
docker exec ragonfire-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" 2>&1 \
  || echo "postgres: DOWN"

echo
echo "=== LightRAG ==="
curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" \
  && echo "lightrag: healthy" || echo "lightrag: DOWN"

echo
echo "=== Disk ==="
[ -f "$PGDATA_IMG" ] && ls -lh "$PGDATA_IMG" | awk '{print "pgdata.img:", $5, $9}' \
  || echo "pgdata.img: MISSING"
