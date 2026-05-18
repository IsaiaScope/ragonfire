#!/usr/bin/env bash
# Stop LightRAG server.
set -euo pipefail

PROJECT_DIR="$HOME/rag-anything"
PID_FILE="$PROJECT_DIR/logs/server.pid"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null || true
    echo "[server] stopped, pid=$PID"
  else
    echo "[server] pid $PID not running"
  fi
  rm -f "$PID_FILE"
else
  # Fallback
  if pkill -f "lightrag-server" 2>/dev/null; then
    echo "[server] killed by pkill"
  else
    echo "[server] not running"
  fi
fi
