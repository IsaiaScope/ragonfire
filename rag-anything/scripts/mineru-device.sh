#!/usr/bin/env bash
# Prints "mps", "cuda", or "cpu" based on local torch capabilities.
# Reads from the host venv at $RAGONFIRE_RUNTIME/.venv.
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init mineru-device
RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
PYTHON="$RUNTIME_DIR/.venv/bin/python"

[ -x "$PYTHON" ] || { echo "cpu"; exit 0; }

"$PYTHON" - <<'PY'
import sys
try:
    import torch
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        print("mps"); sys.exit(0)
    if torch.cuda.is_available():
        print("cuda"); sys.exit(0)
except Exception:
    pass
print("cpu")
PY
