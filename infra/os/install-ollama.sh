#!/usr/bin/env bash
set -euo pipefail
OS=$("$( dirname "${BASH_SOURCE[0]}" )/detect.sh")

if command -v ollama >/dev/null; then
  echo "[ollama] already installed: $(ollama --version 2>&1 | head -1)"
  exit 0
fi

case "$OS" in
  darwin)
    command -v brew >/dev/null || { echo "[ollama] FATAL: Homebrew required on macOS. https://brew.sh" >&2; exit 1; }
    brew install ollama ;;
  linux|wsl)
    curl -fsSL https://ollama.com/install.sh | sh ;;
esac

case "$OS" in
  darwin) brew services start ollama || true ;;
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
  || { echo "[ollama] FATAL: API never came up" >&2; exit 1; }

echo "[ollama] ready"
