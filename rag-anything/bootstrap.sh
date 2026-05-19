#!/usr/bin/env bash
# OS-agnostic installer: Docker check + Ollama + uv + venv + skills + compose build + db-init.
#
# Usage:
#   ./bootstrap.sh                                   # skills -> claude-code
#   ./bootstrap.sh --agent codex
#   ./bootstrap.sh --agent all
#   ./bootstrap.sh --skip-skills
set -euo pipefail
export COPYFILE_DISABLE=1

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$REPO_DIR/.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
PYTHON_VERSION="3.12"
LLM_MODEL="qwen2.5vl:7b"
EMBED_MODEL="bge-m3"

log() { printf "\033[1;36m[bootstrap]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

SKILL_ARGS=()
SKIP_SKILLS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)       SKILL_ARGS+=(--agent "$2"); shift 2 ;;
    --agent=*)     SKILL_ARGS+=("--agent" "${1#*=}"); shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    -h|--help)
      awk 'NR==1 { next } /^[^#]/ { exit } { sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    *) err "unknown arg: $1" ;;
  esac
done

"$REPO_ROOT/infra/os/install-docker.sh"
"$REPO_ROOT/infra/os/install-uv.sh"
"$REPO_ROOT/infra/os/install-ollama.sh"

log "preparing runtime dirs"
mkdir -p "$RUNTIME_DIR"/{scripts,logs}

log "syncing scripts + config from repo to $RUNTIME_DIR"
# Wipe stale scripts so renames/deletions in the repo don't leave orphans.
find "$RUNTIME_DIR/scripts" -mindepth 1 -maxdepth 1 \( -name '*.py' -o -name '*.sh' \) -delete 2>/dev/null || true
cp "$REPO_DIR"/scripts/*.py "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/scripts/*.sh "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/requirements.txt "$RUNTIME_DIR/"
[ -f "$RUNTIME_DIR/.env" ] || cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env"
cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env.example"
chmod +x "$RUNTIME_DIR"/scripts/*.sh "$RUNTIME_DIR"/scripts/*.py

# Stamp RAGONFIRE_REPO_DIR into the runtime .env so scripts find the repo
# regardless of where they're invoked from. Idempotent: replace existing line.
if grep -q '^RAGONFIRE_REPO_DIR=' "$RUNTIME_DIR/.env"; then
  python3 -c "import pathlib,re,sys; p=pathlib.Path(sys.argv[1]); p.write_text(re.sub(r'^RAGONFIRE_REPO_DIR=.*\$', f'RAGONFIRE_REPO_DIR={sys.argv[2]}', p.read_text(), flags=re.M))" "$RUNTIME_DIR/.env" "$REPO_ROOT"
else
  printf '\n# Repo path (set by bootstrap so scripts find infra/* from anywhere)\nRAGONFIRE_REPO_DIR=%s\n' "$REPO_ROOT" >> "$RUNTIME_DIR/.env"
fi

# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

log "ensuring drive paths exist"
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORKING_DIR" "$BACKUPS_DIR" \
         "$OLLAMA_MODELS" "$HF_HOME" "$MINERU_MODELS_DIR" \
         "$(dirname "$PGDATA_IMG")"

export OLLAMA_MODELS
log "pulling ollama models"
for m in "$LLM_MODEL" "$EMBED_MODEL"; do
  if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$m"; then
    log "  $m present"
  else
    log "  pulling $m"
    ollama pull "$m"
  fi
done

if [ ! -d "$RUNTIME_DIR/.venv" ]; then
  log "creating Python $PYTHON_VERSION venv at $RUNTIME_DIR/.venv (internal SSD)"
  uv venv --python "$PYTHON_VERSION" "$RUNTIME_DIR/.venv"
fi

log "installing pinned Python deps"
uv pip install --python "$RUNTIME_DIR/.venv/bin/python" -r "$RUNTIME_DIR/requirements.txt"

"$RUNTIME_DIR/scripts/db-init.sh"

log "building docker images"
find "$REPO_ROOT/infra" -name '._*' -delete
LIGHTRAG_ENV_FILE="$RUNTIME_DIR/.env" docker compose -f "$REPO_ROOT/infra/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" build

if [ "$SKIP_SKILLS" -eq 1 ]; then
  log "skipping skills install"
else
  log "installing skills ${SKILL_ARGS[*]:-(default: claude-code)}"
  "$REPO_ROOT/scripts/install-skills.sh" "${SKILL_ARGS[@]+"${SKILL_ARGS[@]}"}"
fi

cat <<EOF

\033[1;32mBootstrap complete.\033[0m

  Repo:     $REPO_DIR
  Runtime:  $RUNTIME_DIR
  Drive:    /Volumes/Crucial-4T/rag-anything

Next steps:
  /lightrag-start
  /raganything-upload <file>
  /lightrag-query "<question>"
  /lightrag-eject   # before unplugging the drive
EOF
