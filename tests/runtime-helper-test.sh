#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# shellcheck disable=SC1091
source "$REPO_DIR/rag-anything/scripts/lib/ragonfire.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/.env" <<EOF
RAGONFIRE_REPO_DIR=$REPO_DIR
RAGONFIRE_DATA_DIR=$tmp/data
POSTGRES_USER=ragonfire
POSTGRES_DATABASE=ragonfire
POSTGRES_PASSWORD=ragonfire
LIGHTRAG_PORT_EXTERNAL=9622
EOF

RAGONFIRE_ENV_FILE="$tmp/.env"
rf_init runtime-test
rf_load_env

[ "$INPUT_DIR" = "$tmp/data/input" ]
[ "$HOST_LOGS_DIR" = "$tmp/data/logs" ]
[ "$PGDATA_IMG" = "$tmp/data/pgdata.ext4.img" ]
rf_require_runtime_env

quoted=$(rf_command_string echo "hello world" "\$HOME")
[[ "$quoted" == *"hello\\ world"* ]] || { echo "expected quoted command string" >&2; exit 1; }

rf_validate_size 100M
rf_validate_size 1G
if (rf_validate_size 0G) 2>/dev/null; then
  echo "expected invalid size to fail" >&2
  exit 1
fi
if (rf_validate_size 1badM) 2>/dev/null; then
  echo "expected malformed size to fail" >&2
  exit 1
fi

if (rf_confirm_destructive delete-everything "test refusal") </dev/null 2>/dev/null; then
  echo "expected non-tty destructive confirmation to fail" >&2
  exit 1
fi

if (unset POSTGRES_USER; rf_require_env POSTGRES_USER) 2>/dev/null; then
  echo "expected missing env to fail" >&2
  exit 1
fi

echo "[runtime-helper-test] PASS"
