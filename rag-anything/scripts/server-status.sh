#!/usr/bin/env bash
# Check LightRAG server status.
set -euo pipefail

PROJECT_DIR="$HOME/rag-anything"
PID_FILE="$PROJECT_DIR/logs/server.pid"
PORT="${PORT:-9621}"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  PID=$(cat "$PID_FILE")
  if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
    echo "[server] up pid=$PID http://localhost:$PORT"
    exit 0
  else
    echo "[server] pid $PID alive but :$PORT not responding"
    exit 2
  fi
fi

echo "[server] down"
exit 1
