#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../rag-anything/scripts/lib/ragonfire.sh"
rf_init uv
if command -v uv >/dev/null; then
  rf_info "already installed: $(uv --version)"
  exit 0
fi
rf_info "installing uv"
curl -LsSf https://astral.sh/uv/install.sh | sh
# shellcheck disable=SC1090
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
command -v uv >/dev/null || rf_die "install succeeded but uv not on PATH"
rf_info "ready"
