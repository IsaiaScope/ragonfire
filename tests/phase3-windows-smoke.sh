#!/usr/bin/env bash
# Windows native branch smoke. Intended for Git Bash on windows-latest.
# shellcheck disable=SC1091
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMP_RUNTIME=$(mktemp -d)
trap 'rm -rf "$TMP_RUNTIME"' EXIT

cp "$REPO_DIR/rag-anything/.env.example" "$TMP_RUNTIME/.env"
python3 - "$TMP_RUNTIME/.env" "$TMP_RUNTIME" "$REPO_DIR" <<'PY'
from pathlib import Path
import sys

env = Path(sys.argv[1])
root = Path(sys.argv[2])
repo = Path(sys.argv[3])
replacements = {
    "PGDATA_IMG": "C:/ragonfire/pgdata.ext4.img",
    "LOG_DIR": str(root / "logs"),
    "LLM_MODEL": "qwen2.5vl:7b",
}
lines = []
for line in env.read_text().splitlines():
    key = line.split("=", 1)[0] if "=" in line else None
    lines.append(f"{key}={replacements[key]}" if key in replacements else line)
lines.append(f"RAGONFIRE_REPO_DIR={repo}")
env.write_text("\n".join(lines) + "\n")
PY

[ "$(RF_OS_OVERRIDE=windows "$REPO_DIR/infra/os/detect.sh")" = "windows" ]

RF_OS_OVERRIDE=windows RAGONFIRE_RUNTIME="$TMP_RUNTIME" bash -n \
  "$REPO_DIR/rag-anything/bootstrap.sh" \
  "$REPO_DIR/rag-anything/scripts/lightrag-start.sh" \
  "$REPO_DIR/rag-anything/scripts/lightrag-stop.sh" \
  "$REPO_DIR/rag-anything/scripts/lightrag-status.sh" \
  "$REPO_DIR/rag-anything/scripts/lightrag-eject.sh"

# shellcheck source=../rag-anything/scripts/lib/ragonfire.sh
source "$REPO_DIR/rag-anything/scripts/lib/ragonfire.sh"
RF_OS_OVERRIDE=windows RAGONFIRE_RUNTIME="$TMP_RUNTIME" rf_load_env_file "$TMP_RUNTIME/.env"
[ "$RF_OS" = "windows" ]
rf_strip_appledouble

echo "[windows-smoke] PASS"
