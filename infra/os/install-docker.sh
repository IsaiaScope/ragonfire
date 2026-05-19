#!/usr/bin/env bash
# Verifies Docker is installed and the daemon is reachable.
# Does NOT install Docker automatically (too risky to script across OSes).
set -euo pipefail
OS=$("$( dirname "${BASH_SOURCE[0]}" )/detect.sh")

if ! command -v docker >/dev/null; then
  case "$OS" in
    darwin) URL="https://docs.docker.com/desktop/install/mac-install/" ;;
    linux)  URL="https://docs.docker.com/engine/install/" ;;
    wsl)    URL="https://docs.docker.com/desktop/wsl/" ;;
  esac
  echo "[docker] FATAL: docker not installed. Install: $URL" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "[docker] FATAL: docker daemon not running. Start Docker Desktop / dockerd." >&2
  exit 1
fi

docker compose version >/dev/null 2>&1 \
  || { echo "[docker] FATAL: 'docker compose' plugin missing" >&2; exit 1; }

echo "[docker] ready: $(docker --version)"
