#!/usr/bin/env bash
# Shared helpers for RagOnFire shell entrypoints.
# Source this file after `set -euo pipefail`.

if [ "${_RAGONFIRE_SH_INCLUDED:-0}" = "1" ]; then
  return 0
fi
_RAGONFIRE_SH_INCLUDED=1

RF_SCRIPT_NAME="${RF_SCRIPT_NAME:-ragonfire}"

rf_init() {
  RF_SCRIPT_NAME="${1:-ragonfire}"
  RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
  ENV_FILE="${RAGONFIRE_ENV_FILE:-$RUNTIME_DIR/.env}"
}

rf_info() {
  printf '[%s] %s\n' "$RF_SCRIPT_NAME" "$*"
}

rf_warn() {
  printf '[%s] WARN: %s\n' "$RF_SCRIPT_NAME" "$*" >&2
}

rf_die() {
  printf '[%s] FATAL: %s\n' "$RF_SCRIPT_NAME" "$*" >&2
  exit 1
}

rf_command_string() {
  local out="" arg
  for arg in "$@"; do
    printf -v arg '%q' "$arg"
    out="${out}${out:+ }${arg}"
  done
  printf '%s' "$out"
}

rf_run() {
  rf_info "run: $(rf_command_string "$@")"
  "$@"
}

rf_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || rf_die "missing command '$1'. Run rag-anything/bootstrap.sh or install '$1', then retry."
}

rf_require_cmds() {
  local cmd
  for cmd in "$@"; do
    rf_require_cmd "$cmd"
  done
}

rf_require_env() {
  local name="$1"
  [ -n "${!name:-}" ] || rf_die "missing required environment variable '$name' in $ENV_FILE"
}

rf_require_file() {
  [ -f "$1" ] || rf_die "$2: $1"
}

rf_script_repo_fallback() {
  cd "$( dirname "${BASH_SOURCE[0]}" )/../../.." && pwd
}

rf_load_env() {
  rf_require_file "$ENV_FILE" "$ENV_FILE missing - run rag-anything/bootstrap.sh first"
  rf_load_env_file "$ENV_FILE"
}

rf_load_env_or_example() {
  if [ -f "$ENV_FILE" ]; then
    rf_load_env_file "$ENV_FILE"
    return 0
  fi
  REPO_DIR="${RAGONFIRE_REPO_DIR:-$(rf_script_repo_fallback)}"
  ENV_FILE="$REPO_DIR/rag-anything/.env.example"
  rf_require_file "$ENV_FILE" "$ENV_FILE missing"
  rf_load_env_file "$ENV_FILE"
}

rf_load_env_file() {
  ENV_FILE="$1"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  REPO_DIR="${RAGONFIRE_REPO_DIR:-$(rf_script_repo_fallback)}"
  RAGONFIRE_REPO_DIR="$REPO_DIR"
  RAGONFIRE_DATA_DIR="${RAGONFIRE_DATA_DIR:-$REPO_DIR/data}"

  INPUT_DIR="${INPUT_DIR:-$RAGONFIRE_DATA_DIR/input}"
  OUTPUT_DIR="${OUTPUT_DIR:-$RAGONFIRE_DATA_DIR/output}"
  WORKING_DIR="${WORKING_DIR:-$RAGONFIRE_DATA_DIR/working}"
  BACKUPS_DIR="${BACKUPS_DIR:-$RAGONFIRE_DATA_DIR/backups}"
  # Internal SSD, NOT the data drive: ollama reloads GGUF per model swap during
  # ingest; exFAT reloads cost seconds each and dominate runtime (internal ~0.06s).
  OLLAMA_MODELS="${OLLAMA_MODELS:-$HOME/.ollama/models}"
  HF_HOME="${HF_HOME:-$RAGONFIRE_DATA_DIR/hf}"
  MINERU_MODELS_DIR="${MINERU_MODELS_DIR:-$RAGONFIRE_DATA_DIR/mineru}"
  PGDATA_IMG="${PGDATA_IMG:-$RAGONFIRE_DATA_DIR/pgdata.ext4.img}"
  HOST_LOGS_DIR="${HOST_LOGS_DIR:-$RAGONFIRE_DATA_DIR/logs}"
  LOG_DIR="${LOG_DIR:-/var/log/lightrag}"
  RF_OS="${RF_OS:-$("$REPO_DIR/infra/os/detect.sh")}"

  export REPO_DIR RUNTIME_DIR ENV_FILE RAGONFIRE_REPO_DIR RAGONFIRE_DATA_DIR
  export INPUT_DIR OUTPUT_DIR WORKING_DIR BACKUPS_DIR OLLAMA_MODELS HF_HOME
  export MINERU_MODELS_DIR PGDATA_IMG HOST_LOGS_DIR LOG_DIR RF_OS
}

rf_require_runtime_env() {
  rf_require_env POSTGRES_USER
  rf_require_env POSTGRES_DATABASE
  rf_require_env POSTGRES_PASSWORD
  rf_require_env LIGHTRAG_PORT_EXTERNAL
  rf_require_env PGDATA_IMG
}

rf_ensure_data_dirs() {
  rf_info "data root: $RAGONFIRE_DATA_DIR"
  rf_run mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORKING_DIR" "$BACKUPS_DIR" \
    "$OLLAMA_MODELS" "$HF_HOME" "$MINERU_MODELS_DIR" "$HOST_LOGS_DIR" \
    "$(dirname "$PGDATA_IMG")"
}

rf_compose() {
  rf_require_cmd docker
  docker compose version >/dev/null 2>&1 || rf_die "docker compose is not available. Install Docker Compose v2, then retry."
  rf_info "compose: docker compose -f $REPO_DIR/infra/docker-compose.yml --env-file $ENV_FILE $*"
  LIGHTRAG_ENV_FILE="$ENV_FILE" docker compose -f "$REPO_DIR/infra/docker-compose.yml" --env-file "$ENV_FILE" "$@"
}

rf_pg_exec() {
  rf_require_cmd docker
  rf_info "postgres: $*"
  docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" "$@"
}

rf_pg_query() {
  rf_require_cmd docker
  docker exec ragonfire-postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" -tAc "$1"
}

rf_wait_http() {
  local label="$1" url="$2" attempts="${3:-30}" sleep_seconds="${4:-2}" i last_error
  rf_require_cmd curl
  rf_info "waiting for $label: $url"
  for i in $(seq 1 "$attempts"); do
    last_error=$(curl -sfS "$url" 2>&1 >/dev/null) && {
      rf_info "$label healthy after attempt $i/$attempts"
      return 0
    }
    rf_info "$label not ready ($i/$attempts): ${last_error:-no response}; retrying in ${sleep_seconds}s"
    sleep "$sleep_seconds"
  done
  rf_die "$label did not become healthy at $url. Check logs in $HOST_LOGS_DIR and run /lightrag-status."
}

rf_confirm_destructive() {
  local token="$1" message="$2" answer
  if [ "${RAGONFIRE_ASSUME_YES:-0}" = "1" ]; then
    rf_warn "RAGONFIRE_ASSUME_YES=1; bypassing confirmation for $token"
    return 0
  fi
  [ -t 0 ] || rf_die "refusing destructive action without a TTY. Set RAGONFIRE_ASSUME_YES=1 only for CI/test automation."
  printf '[%s] DESTRUCTIVE: %s\n' "$RF_SCRIPT_NAME" "$message" >&2
  printf '[%s] Type %s to continue: ' "$RF_SCRIPT_NAME" "$token" >&2
  read -r answer
  [ "$answer" = "$token" ] || rf_die "confirmation did not match; aborted"
}

rf_validate_size() {
  [[ "$1" =~ ^[1-9][0-9]*[MGT]$ ]] || rf_die "invalid size '$1' (expected examples: 100M, 100G, 1T)"
}

rf_size_bytes() {
  rf_require_cmd python3
  python3 - "$1" <<'PY'
import re
import sys

raw = sys.argv[1].strip().upper()
match = re.fullmatch(r"([1-9][0-9]*)([MGT])", raw)
if not match:
    raise SystemExit(2)
value = int(match.group(1))
scale = {"M": 1024**2, "G": 1024**3, "T": 1024**4}[match.group(2)]
print(value * scale)
PY
}

rf_strip_appledouble() {
  [ "${RF_OS:-}" = "darwin" ] || return 0

  local path
  for path in "$@"; do
    [ -e "$path" ] || continue
    rf_info "cleaning AppleDouble files under $path"
    find "$path" -name '._*' -delete 2>/dev/null || true
  done
}

rf_ollama_running() {
  case "${RF_OS:-}" in
    windows)
      tasklist /FI "IMAGENAME eq ollama.exe" 2>/dev/null | grep -qi "^ollama.exe"
      ;;
    *)
      command -v pgrep >/dev/null 2>&1 && pgrep -x ollama >/dev/null
      ;;
  esac
}

rf_ollama_serve_bg() {
  case "${RF_OS:-}" in
    windows)
      powershell -NoProfile -Command "Start-Process -WindowStyle Hidden ollama 'serve'"
      ;;
    *)
      rf_run mkdir -p "$HOST_LOGS_DIR"
      nohup ollama serve >"$HOST_LOGS_DIR/ollama.log" 2>&1 &
      ;;
  esac
}

rf_ollama_stop_model() {
  local model="$1"
  command -v ollama >/dev/null 2>&1 && ollama stop "$model" 2>/dev/null || true
}

rf_eject_drive() {
  local drive_root="$1"
  local dev letter

  case "${RF_OS:-}" in
    darwin)
      rf_run diskutil eject "$drive_root"
      ;;
    linux|wsl)
      dev=$(findmnt -no SOURCE "$drive_root" || true)
      if [ -n "$dev" ]; then
        rf_run udisksctl unmount -b "$dev"
        rf_run udisksctl power-off -b "$dev"
      else
        rf_warn "manual unmount required: umount $drive_root"
      fi
      ;;
    windows)
      letter=$(printf '%s' "$drive_root" | sed -E 's@^/?([A-Za-z]):?.*@\1@')
      if [ -z "$letter" ] || [ "$letter" = "$drive_root" ]; then
        rf_warn "manual eject required: $drive_root"
        return 0
      fi
      rf_run powershell -NoProfile -Command \
        "(New-Object -ComObject Shell.Application).Namespace(17).ParseName('${letter}:').InvokeVerb('Eject')"
      ;;
    *)
      rf_warn "manual eject required for unsupported OS '${RF_OS:-unknown}': $drive_root"
      ;;
  esac
}

rf_tail_file() {
  local file="$1" lines="${2:-40}"
  [ -f "$file" ] || return 0
  rf_info "last $lines lines of $file"
  tail -n "$lines" "$file" || true
}
