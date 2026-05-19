#!/usr/bin/env bash
# Cleanly stops the whole stack so the drive can be ejected safely.
set -euo pipefail

RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
ENV_FILE="$RUNTIME_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "[stop] FATAL: $ENV_FILE missing" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
REPO_DIR="${RAGONFIRE_REPO_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )}"

COMPOSE="docker compose -f $REPO_DIR/infra/docker-compose.yml --env-file $ENV_FILE"

echo "[stop] graceful compose down (PG checkpoint + loop unmount)"
LIGHTRAG_ENV_FILE="$ENV_FILE" $COMPOSE down

if pgrep -x ollama >/dev/null; then
  echo "[stop] unloading qwen2.5vl from Ollama"
  ollama stop qwen2.5vl:7b 2>/dev/null || true
fi

echo "[stop] OK"
