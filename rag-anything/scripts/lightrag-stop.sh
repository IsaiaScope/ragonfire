#!/usr/bin/env bash
# Cleanly stops the whole stack so the drive can be ejected safely.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init stop
rf_load_env
rf_require_runtime_env
rf_require_cmd docker

rf_info "graceful compose down (PG checkpoint + loop unmount)"
rf_compose down

if command -v pgrep >/dev/null 2>&1 && pgrep -x ollama >/dev/null; then
  rf_info "unloading qwen2.5vl from Ollama"
  command -v ollama >/dev/null 2>&1 && ollama stop qwen2.5vl:7b 2>/dev/null || true
fi

# macOS keeps writing AppleDouble shadows onto ExFAT while containers/ingests
# run. Sweep them so the drive stays clean before eject.
rf_strip_appledouble "$RAGONFIRE_DATA_DIR" "$REPO_DIR/infra"

rf_info "OK"
