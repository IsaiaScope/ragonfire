#!/usr/bin/env bash
# OS-agnostic installer: Docker check + Ollama + uv + venv + skills + compose build + db-init.
#
# Usage:
#   ./bootstrap.sh                                   # no skill copy: Claude Code reads .claude/skills/
#   ./bootstrap.sh --agent codex                     # also copy skills -> ~/.codex/skills
#   ./bootstrap.sh --agent all
#   ./bootstrap.sh --skip-skills
# shellcheck disable=SC1091
set -euo pipefail
export COPYFILE_DISABLE=1

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$REPO_DIR/.." && pwd )"
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
PYTHON_VERSION="3.12"
LLM_MODEL="qwen2.5vl:7b"       # vision/image extraction
EXTRACTION_MODEL="qwen2.5:7b"  # text entity extraction (LightRAG tuple format)
EMBED_MODEL="bge-m3"
RF_OS=$("$REPO_ROOT/infra/os/detect.sh")

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

if [ "$RF_OS" = "windows" ]; then
  case "$(uname -s)" in
    MINGW*|MSYS*) ;;
    *) err "Windows native bootstrap must run from Git Bash, not PowerShell/CMD/WSL." ;;
  esac
fi

"$REPO_ROOT/infra/os/install-docker.sh"
"$REPO_ROOT/infra/os/install-uv.sh"
"$REPO_ROOT/infra/os/install-ollama.sh"

log "preparing runtime dirs"
mkdir -p "$RUNTIME_DIR"/{scripts,logs} "$RUNTIME_DIR/scripts/lib"

log "syncing scripts + config from repo to $RUNTIME_DIR"
# Wipe stale scripts so renames/deletions in the repo don't leave orphans.
find "$RUNTIME_DIR/scripts" -mindepth 1 -maxdepth 1 \( -name '*.py' -o -name '*.sh' \) -delete 2>/dev/null || true
rm -rf "$RUNTIME_DIR/scripts/lib"
mkdir -p "$RUNTIME_DIR/scripts/lib"
cp "$REPO_DIR"/scripts/*.py "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/scripts/*.sh "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR"/scripts/lib/*.sh "$RUNTIME_DIR/scripts/lib/"
cp "$REPO_DIR"/requirements.txt "$RUNTIME_DIR/"
cp "$REPO_DIR"/requirements.lock "$RUNTIME_DIR/"
[ -f "$RUNTIME_DIR/.env" ] || cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env"
cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env.example"
chmod +x "$RUNTIME_DIR"/scripts/*.sh "$RUNTIME_DIR"/scripts/*.py

# Stamp concrete repo/data paths into runtime .env so copied scripts can run
# from ~/rag-anything while all persistent state stays under repo-root data/.
python3 "$RUNTIME_DIR/scripts/render_env.py" "$RUNTIME_DIR/.env" --repo-root "$REPO_ROOT"

# shellcheck disable=SC1090
set -a; source "$RUNTIME_DIR/.env"; set +a

log "ensuring drive paths exist"
mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORKING_DIR" "$BACKUPS_DIR" \
         "$OLLAMA_MODELS" "$HF_HOME" \
         "$(dirname "$PGDATA_IMG")"

export OLLAMA_MODELS
log "pulling ollama models"
for m in "$LLM_MODEL" "$EXTRACTION_MODEL" "$EMBED_MODEL"; do
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
uv pip install --python "$RUNTIME_DIR/.venv/bin/python" -r "$RUNTIME_DIR/requirements.lock"

"$RUNTIME_DIR/scripts/db-init.sh"

log "building docker images"
if [ "$RF_OS" = "darwin" ]; then
  find "$REPO_ROOT/infra" -name '._*' -delete
fi
MSYS_NO_PATHCONV=1 LIGHTRAG_ENV_FILE="$RUNTIME_DIR/.env" docker compose -f "$REPO_ROOT/infra/docker-compose.yml" --env-file "$RUNTIME_DIR/.env" build

if [ "$SKIP_SKILLS" -eq 1 ] || [ ${#SKILL_ARGS[@]} -eq 0 ]; then
  # ponytail: no --agent means Claude Code, which loads .claude/skills/ from the repo directly.
  log "skills stay project-local in .claude/skills/ (pass --agent to copy them elsewhere)"
else
  log "installing skills ${SKILL_ARGS[*]}"
  "$REPO_ROOT/scripts/install-skills.sh" "${SKILL_ARGS[@]}"
fi

cat <<EOF

\033[1;32mBootstrap complete.\033[0m

  Repo:     $REPO_DIR
  Runtime:  $RUNTIME_DIR
  Data:     $REPO_ROOT/data  (pgdata.ext4.img, ollama/, hf/, mineru/, input/, output/, working/, backups/)

Next steps:
  /lightrag-start
  /raganything-upload <file>
  /lightrag-query "<question>"
  /lightrag-eject   # before unplugging the drive
EOF
