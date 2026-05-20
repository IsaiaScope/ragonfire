#!/usr/bin/env bash
# Verifies Docker is installed and the daemon is reachable.
# Does NOT install Docker automatically (too risky to script across OSes).
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../rag-anything/scripts/lib/ragonfire.sh"
rf_init docker
OS=$("$SCRIPT_DIR/detect.sh")

if ! command -v docker >/dev/null; then
  case "$OS" in
    darwin) URL="https://docs.docker.com/desktop/install/mac-install/" ;;
    linux)  URL="https://docs.docker.com/engine/install/" ;;
    wsl)    URL="https://docs.docker.com/desktop/wsl/" ;;
  esac
  rf_die "docker not installed. Install: $URL"
fi

if ! docker info >/dev/null 2>&1; then
  rf_die "docker daemon not running. Start Docker Desktop / dockerd."
fi

docker compose version >/dev/null 2>&1 \
  || rf_die "'docker compose' plugin missing"

rf_info "ready: $(docker --version)"
