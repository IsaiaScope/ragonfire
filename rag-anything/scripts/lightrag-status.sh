#!/usr/bin/env bash
# Quick health snapshot of the whole stack.
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init status
rf_load_env
rf_require_runtime_env

rf_info "repo: $REPO_DIR"
rf_info "runtime: $RUNTIME_DIR"
rf_info "data: $RAGONFIRE_DATA_DIR"

echo "=== Ollama ==="
rf_ollama_running && echo "daemon: running" || echo "daemon: STOPPED"
command -v curl >/dev/null 2>&1 && curl -sf http://localhost:11434/api/tags >/dev/null && echo "api: 200" || echo "api: DOWN"

echo
echo "=== Docker ==="
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  rf_compose ps || echo "compose: DOWN"
else
  echo "docker compose: unavailable"
fi

echo
echo "=== Postgres ==="
if command -v docker >/dev/null 2>&1; then
  docker exec ragonfire-postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" 2>&1 \
    || echo "postgres: DOWN"
else
  echo "postgres: UNKNOWN (docker unavailable)"
fi

echo
echo "=== LightRAG ==="
command -v curl >/dev/null 2>&1 && curl -sf "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" \
  && echo "lightrag: healthy" || echo "lightrag: DOWN"

echo
echo "=== Disk ==="
# shellcheck disable=SC2012
[ -f "$PGDATA_IMG" ] && ls -lh "$PGDATA_IMG" | awk '{print "pgdata.img:", $5, $9}' \
  || echo "pgdata.img: MISSING"
[ -d "$HOST_LOGS_DIR" ] && echo "logs: $HOST_LOGS_DIR" || echo "logs: MISSING ($HOST_LOGS_DIR)"
