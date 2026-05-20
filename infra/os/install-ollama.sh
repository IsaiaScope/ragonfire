#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../rag-anything/scripts/lib/ragonfire.sh"
rf_init ollama
OS=$("$SCRIPT_DIR/detect.sh")

if command -v ollama >/dev/null; then
  rf_info "already installed: $(ollama --version 2>&1 | head -1)"
  exit 0
fi

case "$OS" in
  darwin)
    command -v brew >/dev/null || rf_die "Homebrew required on macOS. https://brew.sh"
    rf_run brew install ollama ;;
  linux|wsl)
    rf_info "installing via official Ollama installer"
    curl -fsSL https://ollama.com/install.sh | sh ;;
esac

case "$OS" in
  darwin) rf_info "starting Ollama service"; brew services start ollama || true ;;
  linux|wsl)
    if command -v systemctl >/dev/null; then
      sudo systemctl enable --now ollama 2>/dev/null || nohup ollama serve >/tmp/ollama.log 2>&1 &
    else
      nohup ollama serve >/tmp/ollama.log 2>&1 &
    fi ;;
esac

for _ in $(seq 1 15); do
  curl -sf http://localhost:11434/api/tags >/dev/null && break
  sleep 1
done
curl -sf http://localhost:11434/api/tags >/dev/null \
  || rf_die "API never came up"

rf_info "ready"
