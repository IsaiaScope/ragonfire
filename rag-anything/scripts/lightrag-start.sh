#!/usr/bin/env bash
# Boots the whole stack: Ollama (native) + Postgres (container) + LightRAG (container).
# Verifies schema version stamp matches the pinned lightrag-hku version.
set -euo pipefail
export COPYFILE_DISABLE=1

RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "[start] FATAL: $ENV_FILE missing - run bootstrap.sh first" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
# REPO_DIR after .env so RAGONFIRE_REPO_DIR loaded from .env wins
# over the fallback (script's own dir + ../..).
REPO_DIR="${RAGONFIRE_REPO_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )}"
mkdir -p "$RUNTIME_DIR/logs"

[ -f "$PGDATA_IMG" ] || { echo "[start] FATAL: $PGDATA_IMG missing - run scripts/db-init.sh first" >&2; exit 1; }

if ! pgrep -x ollama >/dev/null; then
  echo "[start] launching ollama serve in background"
  nohup ollama serve >"$RUNTIME_DIR/logs/ollama.log" 2>&1 &
  sleep 2
fi
for _ in $(seq 1 15); do
  curl -sf http://localhost:11434/api/tags >/dev/null && break
  sleep 1
done

COMPOSE="docker compose -f $REPO_DIR/infra/docker-compose.yml --env-file $ENV_FILE"

# Strip macOS AppleDouble shadow files (._*) that ExFAT cannot suppress.
# They break docker build context and pollute mounted volumes.
find "$REPO_DIR/infra" -name '._*' -delete 2>/dev/null || true
find "$(dirname "$PGDATA_IMG")" -maxdepth 1 -name '._*' -delete 2>/dev/null || true

echo "[start] docker compose up"
LIGHTRAG_ENV_FILE="$ENV_FILE" $COMPOSE up -d

echo "[start] waiting for lightrag-server :${LIGHTRAG_PORT_EXTERNAL}/health"
for _ in $(seq 1 60); do
  curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" >/dev/null && break
  sleep 2
done
curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" >/dev/null \
  || { echo "[start] FATAL: lightrag-server never healthy"; exit 1; }

EXPECTED=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
STORED=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
  "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || echo "")
if [ -z "$STORED" ]; then
  echo "[start] first run: stamping lightrag_version=$EXPECTED"
  docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -c \
    "INSERT INTO lightrag_meta(key,value) VALUES ('lightrag_version','$EXPECTED') \
     ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()"
elif [ "$STORED" != "$EXPECTED" ]; then
  echo "[start] FATAL: schema=$STORED, code=$EXPECTED - run /lightrag-upgrade" >&2
  exit 1
fi

echo "[start] OK - http://localhost:${LIGHTRAG_PORT_EXTERNAL}"
