#!/usr/bin/env bash
set -euo pipefail
if command -v uv >/dev/null; then
  echo "[uv] already installed: $(uv --version)"
  exit 0
fi
curl -LsSf https://astral.sh/uv/install.sh | sh
# shellcheck disable=SC1090
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env" || true
command -v uv >/dev/null || { echo "[uv] FATAL: install succeeded but uv not on PATH" >&2; exit 1; }
echo "[uv] ready"
