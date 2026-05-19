#!/usr/bin/env bash
# Ingest sample.pdf, query, assert known phrase appears, assert graph has entities.
set -euo pipefail
REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
export COPYFILE_DISABLE=1

if [ -n "${RAGONFIRE_RUNTIME:-}" ]; then
  RUNTIME_DIR="$RAGONFIRE_RUNTIME"
  CLEAN_RUNTIME=0
else
  RUNTIME_DIR="${SMOKE_RUNTIME_DIR:-/tmp/ragonfire-phase2-runtime}"
  CLEAN_RUNTIME=1
fi

if [ "$CLEAN_RUNTIME" -eq 1 ]; then
  DATA_DIR=$(mktemp -d)
  trap 'LIGHTRAG_ENV_FILE="$RUNTIME_DIR/.env" docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" down -v 2>/dev/null || true; rm -rf "$DATA_DIR"' EXIT

  mkdir -p "$RUNTIME_DIR"/{scripts,logs}
  cp "$REPO_DIR"/rag-anything/scripts/*.py "$RUNTIME_DIR/scripts/"
  cp "$REPO_DIR"/rag-anything/scripts/*.sh "$RUNTIME_DIR/scripts/"
  cp "$REPO_DIR"/rag-anything/requirements.txt "$RUNTIME_DIR/"
  cp "$REPO_DIR"/rag-anything/.env.example "$RUNTIME_DIR/.env"
  chmod +x "$RUNTIME_DIR"/scripts/*.sh "$RUNTIME_DIR"/scripts/*.py

  python3 - "$RUNTIME_DIR/.env" "$DATA_DIR" <<'PY'
from pathlib import Path
import sys

env = Path(sys.argv[1])
data = Path(sys.argv[2])
replacements = {
    "PGDATA_IMG": str(data / "pgdata.ext4.img"),
    "PGDATA_IMG_CAP": "500M",
    "INPUT_DIR": str(data / "input"),
    "OUTPUT_DIR": str(data / "output"),
    "WORKING_DIR": str(data / "working"),
    "BACKUPS_DIR": str(data / "backups"),
    "HF_HOME": str(data / "models/hf"),
    "MINERU_MODELS_DIR": str(data / "models/mineru"),
    "OLLAMA_MODELS": str(data / "models/ollama"),
    "LOG_DIR": str(data / "logs"),
}
lines = []
for line in env.read_text().splitlines():
    key = line.split("=", 1)[0] if "=" in line else None
    if key in replacements:
        lines.append(f"{key}={replacements[key]}")
    else:
        lines.append(line)
env.write_text("\n".join(lines) + "\n")
PY

  if [ ! -d "$RUNTIME_DIR/.venv" ]; then
    uv venv --python 3.12 "$RUNTIME_DIR/.venv"
  fi
  uv pip install --python "$RUNTIME_DIR/.venv/bin/python" -r "$RUNTIME_DIR/requirements.txt"
  PGDATA_IMG="$DATA_DIR/pgdata.ext4.img" PGDATA_IMG_CAP=500M RAGONFIRE_RUNTIME="$RUNTIME_DIR" \
    "$RUNTIME_DIR/scripts/db-init.sh"
  find "$REPO_DIR/infra" -name '._*' -delete
  LIGHTRAG_ENV_FILE="$RUNTIME_DIR/.env" docker compose -f "$REPO_DIR/infra/docker-compose.yml" \
    --env-file "$RUNTIME_DIR/.env" build
fi

export RAGONFIRE_RUNTIME="$RUNTIME_DIR"
# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

PORT="${LIGHTRAG_PORT_EXTERNAL:-9622}"

echo "[smoke] /lightrag-start"
"$REPO_DIR/rag-anything/scripts/lightrag-start.sh"

echo "[smoke] ingest sample.pdf"
"$RUNTIME_DIR/.venv/bin/python" "$RUNTIME_DIR/scripts/ingest.py" \
  "$REPO_DIR/tests/fixtures/sample.pdf"

echo "[smoke] querying"
ANSWER=$(curl -sf -X POST "http://localhost:$PORT/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is the Marble Crocodile method?", "mode": "hybrid"}')
echo "$ANSWER" | grep -iq "marble crocodile" \
  || { echo "[smoke] FAIL: known phrase missing from answer"; exit 1; }

echo "[smoke] checking graph has entities"
COUNT=$(docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc \
  "SELECT count(*) FROM ag_catalog.ag_graph")
[ "$COUNT" -ge 1 ] || { echo "[smoke] FAIL: no AGE graphs"; exit 1; }

echo "[smoke] PASS"
