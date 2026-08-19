#!/usr/bin/env bash
# Cleanly stops the whole stack so the drive can be ejected safely.
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_bootstrap stop
rf_require_cmd docker

rf_info "graceful compose down (PG checkpoint + loop unmount)"
rf_compose down

if rf_ollama_running; then
  rf_info "unloading $LLM_MODEL from Ollama"
  rf_ollama_stop_model "$LLM_MODEL"
fi

# macOS keeps writing AppleDouble shadows onto ExFAT while containers/ingests
# run. Sweep them so the drive stays clean before eject.
rf_strip_appledouble "$RAGONFIRE_DATA_DIR" "$REPO_DIR/infra"

rf_info "OK"
