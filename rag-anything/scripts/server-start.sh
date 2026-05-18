#!/usr/bin/env bash
# Start LightRAG server in background. Idempotent.
set -euo pipefail

PROJECT_DIR="$HOME/rag-anything"
PID_FILE="$PROJECT_DIR/logs/server.pid"
LOG_FILE="$PROJECT_DIR/logs/server.log"
PORT="${PORT:-9621}"

cd "$PROJECT_DIR"
mkdir -p logs

# Already running?
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "[server] already running, pid=$(cat "$PID_FILE")"
  exit 0
fi

# Stale PID
[ -f "$PID_FILE" ] && rm -f "$PID_FILE"

# Ollama up?
if ! curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
  echo "[server] starting ollama"
  brew services start ollama >/dev/null 2>&1 || ollama serve >/dev/null 2>&1 &
  for _ in {1..15}; do
    curl -sf http://localhost:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi

# Load .env into shell env so lightrag-server inherits it
set -a
# shellcheck disable=SC1091
. "$PROJECT_DIR/.env"
set +a

echo "[server] starting lightrag-server on :$PORT"
nohup "$PROJECT_DIR/.venv/bin/lightrag-server" >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"

# Wait for HTTP
for _ in {1..30}; do
  if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
    echo "[server] up, pid=$(cat "$PID_FILE"), http://localhost:$PORT"
    exit 0
  fi
  sleep 1
done

echo "[server] failed to come up. Last 20 lines of log:"
tail -20 "$LOG_FILE"
exit 1
