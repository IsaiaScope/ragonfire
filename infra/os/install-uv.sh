#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../rag-anything/scripts/lib/ragonfire.sh"
rf_init uv
OS=$("$SCRIPT_DIR/detect.sh")

if command -v uv >/dev/null; then
  rf_info "already installed: $(uv --version)"
  exit 0
fi

case "$OS" in
  windows)
    rf_info "installing uv via PowerShell installer"
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    ;;
  *)
    rf_info "installing uv"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # shellcheck disable=SC1090
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
    ;;
esac

PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
command -v uv >/dev/null || rf_die "install succeeded but uv not on PATH"
rf_info "ready"
