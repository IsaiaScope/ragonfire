#!/usr/bin/env bash
# Boots the whole stack: Ollama (native) + Postgres (container) + LightRAG (container).
# Verifies schema version stamp matches the pinned lightrag-hku version.
# shellcheck disable=SC1091
set -euo pipefail
export COPYFILE_DISABLE=1

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init start
rf_load_env
rf_require_runtime_env
rf_require_cmds curl docker grep ollama sed
rf_ensure_data_dirs

rf_require_file "$PGDATA_IMG" "$PGDATA_IMG missing - run scripts/db-init.sh first"

if ! rf_ollama_running; then
  rf_info "launching ollama serve in background; log: $HOST_LOGS_DIR/ollama.log"
  rf_ollama_serve_bg
  sleep 2
fi
rf_wait_http "ollama" "http://localhost:11434/api/tags" 15 1

# Strip macOS AppleDouble shadow files (._*) that ExFAT cannot suppress.
# They break docker build context and pollute mounted volumes.
rf_strip_appledouble "$REPO_DIR/infra" "$(dirname "$PGDATA_IMG")"

rf_info "docker compose up"
rf_compose up -d

rf_wait_http "lightrag-server" "http://localhost:${LIGHTRAG_PORT_EXTERNAL}/health" 60 2

EXPECTED=$(grep -E '^lightrag-hku\[api\]==' "$REPO_DIR/rag-anything/requirements.txt" | sed 's/.*==//')
[ -n "$EXPECTED" ] || rf_die "cannot read lightrag-hku pin from $REPO_DIR/rag-anything/requirements.txt"
STORED=$(rf_pg_query "SELECT value FROM lightrag_meta WHERE key='lightrag_version'" 2>/dev/null || echo "")
if [ -z "$STORED" ]; then
  rf_info "first run: stamping lightrag_version=$EXPECTED"
  rf_pg_exec -c \
    "INSERT INTO lightrag_meta(key,value) VALUES ('lightrag_version','$EXPECTED') \
     ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_at=now()"
elif [ "$STORED" != "$EXPECTED" ]; then
  rf_die "schema=$STORED, code=$EXPECTED - run /lightrag-upgrade"
fi

rf_info "OK - http://localhost:${LIGHTRAG_PORT_EXTERNAL}"
