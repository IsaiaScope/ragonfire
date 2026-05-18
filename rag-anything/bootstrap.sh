#!/usr/bin/env bash
# RagOnFire bootstrap for macOS (Apple Silicon)
# One-shot installer:
#   - Ollama (brew) + qwen2.5vl:7b + bge-m3
#   - Python 3.12 venv at ~/rag-anything/.venv (internal SSD; exFAT breaks venvs)
#   - raganything[all] + lightrag-hku[api] + mineru + ollama python client
#   - 7 Claude Code skills copied to ~/.claude/skills/
#   - Runtime data dirs on /Volumes/Crucial-4T/rag-anything/
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"   # ragonfire/rag-anything
RUNTIME_DIR="$HOME/rag-anything"
DATA_DIR="/Volumes/Crucial-4T/rag-anything"
SKILLS_TARGET="$HOME/.claude/skills"
PYTHON_VERSION="3.12"
LLM_MODEL="qwen2.5vl:7b"
EMBED_MODEL="bge-m3"

log() { printf "\033[1;36m[bootstrap]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; exit 1; }

# 1. Prereq checks
command -v brew >/dev/null || err "Homebrew required. Install: https://brew.sh"
command -v uv >/dev/null   || err "uv required. Install: curl -LsSf https://astral.sh/uv/install.sh | sh"

[ -d "/Volumes/Crucial-4T" ] || err "Crucial-4T not mounted. Plug it in before running bootstrap."

# 2. Runtime dirs
log "Preparing runtime dirs"
mkdir -p "$RUNTIME_DIR"/{scripts,logs}
mkdir -p "$DATA_DIR"/{storage,output,input}

# 3. Copy scripts + .env + requirements from repo → runtime
log "Syncing scripts + configs from repo to $RUNTIME_DIR"
cp "$REPO_DIR/scripts/"*.py "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR/scripts/"*.sh "$RUNTIME_DIR/scripts/"
cp "$REPO_DIR/requirements.txt" "$RUNTIME_DIR/"
[ -f "$RUNTIME_DIR/.env" ] || cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env"
cp "$REPO_DIR/.env.example" "$RUNTIME_DIR/.env.example"
chmod +x "$RUNTIME_DIR/scripts/"*.sh "$RUNTIME_DIR/scripts/"*.py

# 4. Ollama install + service
if ! command -v ollama >/dev/null; then
  log "Installing ollama via brew"
  brew install ollama
else
  log "ollama present: $(ollama --version 2>&1 | head -1)"
fi

if ! pgrep -x ollama >/dev/null; then
  log "Starting ollama service"
  brew services start ollama
  sleep 3
fi

# Wait for ollama API
for _ in {1..15}; do
  curl -sf http://localhost:11434/api/tags >/dev/null && break
  sleep 1
done

# 5. Pull models
for m in "$LLM_MODEL" "$EMBED_MODEL"; do
  if ollama list | awk 'NR>1 {print $1}' | grep -qx "$m"; then
    log "model present: $m"
  else
    log "Pulling $m (large download)"
    ollama pull "$m"
  fi
done

# 6. Python venv via uv (Python 3.12, isolated from system Python)
if [ ! -d "$RUNTIME_DIR/.venv" ]; then
  log "Creating Python $PYTHON_VERSION venv via uv"
  uv venv --python "$PYTHON_VERSION" "$RUNTIME_DIR/.venv"
fi

# 7. Install Python deps
log "Installing Python packages (raganything[all] + lightrag-hku[api])"
uv pip install --python "$RUNTIME_DIR/.venv/bin/python" -r "$RUNTIME_DIR/requirements.txt"

# 8. MinerU model download (first import triggers download to ~/.mineru/)
log "Triggering MinerU import (models lazy-download on first ingest)"
"$RUNTIME_DIR/.venv/bin/python" -c "
import os
os.environ.setdefault('MINERU_DEVICE', 'mps')
try:
    from mineru.cli.common import prepare_env  # noqa: F401
    print('MinerU import OK')
except Exception as e:
    print(f'MinerU import note: {e}')
" || log "MinerU first-import skipped (will download on first ingest)"

# 9. Install Claude Code skills
log "Installing Claude Code skills to $SKILLS_TARGET"
mkdir -p "$SKILLS_TARGET"
for skill_dir in "$REPO_DIR/skills/"*/; do
  name=$(basename "$skill_dir")
  mkdir -p "$SKILLS_TARGET/$name"
  cp "$skill_dir/SKILL.md" "$SKILLS_TARGET/$name/SKILL.md"
  log "  installed skill: $name"
done

# 10. Verify
log "Verifying lightrag-server installed"
"$RUNTIME_DIR/.venv/bin/lightrag-server" --help >/dev/null 2>&1 && log "lightrag-server OK" || err "lightrag-server missing"

cat <<EOF

\033[1;32mBootstrap complete.\033[0m

  Repo (source):  $REPO_DIR
  Runtime:        $RUNTIME_DIR
  Data:           $DATA_DIR
  Skills:         $SKILLS_TARGET

Next steps:
  /lightrag-start                    # boot server
  /raganything-upload <file>         # ingest multimodal doc
  /lightrag-query "<question>"       # ask the KG
  /lightrag-stop                     # free RAM when done

EOF
