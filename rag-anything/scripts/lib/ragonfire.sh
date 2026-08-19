#!/usr/bin/env bash
# Shared helpers for RagOnFire shell entrypoints.
# Source this file after `set -euo pipefail`.

if [ "${_RAGONFIRE_SH_INCLUDED:-0}" = "1" ]; then
  return 0
fi
_RAGONFIRE_SH_INCLUDED=1

RF_SCRIPT_NAME="${RF_SCRIPT_NAME:-ragonfire}"
RF_PG_CONTAINER="${RF_PG_CONTAINER:-ragonfire-postgres}"

rf_init() {
  RF_SCRIPT_NAME="${1:-ragonfire}"
  RUNTIME_DIR="${RAGONFIRE_RUNTIME:-$HOME/rag-anything}"
  ENV_FILE="${RAGONFIRE_ENV_FILE:-$RUNTIME_DIR/.env}"
}

# Standard entrypoint preamble: name + .env load + runtime-env validation, the
# trio repeated by every lifecycle script. Scripts add their own rf_require_cmds.
rf_bootstrap() {
  rf_init "$1"
  rf_load_env
  rf_require_runtime_env
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

  # Prefer the repo root derived from this script's own location: when infra/
  # sits beside the scripts (CI, dev checkout) that is authoritative and any
  # RAGONFIRE_REPO_DIR carried in .env/.env.example (e.g. a foreign Crucial-4T
  # path) must NOT win. Only when scripts were copied out to the runtime
  # (~/rag-anything, no infra/ sibling) do we trust the stamped env value.
  local fallback_repo
  fallback_repo="$(rf_script_repo_fallback)"
  if [ -f "$fallback_repo/infra/os/detect.sh" ]; then
    REPO_DIR="$fallback_repo"
  else
    REPO_DIR="${RAGONFIRE_REPO_DIR:-$fallback_repo}"
  fi
  RAGONFIRE_REPO_DIR="$REPO_DIR"
  RAGONFIRE_DATA_DIR="${RAGONFIRE_DATA_DIR:-$REPO_DIR/data}"

  # Data Root layout fallbacks. render_env.py:runtime_path_updates() is the
  # authority and stamps these into .env at init; these defaults only fire for an
  # .env that predates a var. Keep the subdir names in sync with render_env.py --
  # DataRootLayoutConsistencyTests fails CI if they drift.
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
  # Host-local Ollama API base for lifecycle probes. The .env's LLM_BINDING_HOST
  # points at host.docker.internal (the container's view); bash runs on the host,
  # so probes use localhost. One default here, consumed by start/status.
  RF_OLLAMA_URL="${RF_OLLAMA_URL:-http://localhost:11434}"

  export REPO_DIR RUNTIME_DIR ENV_FILE RAGONFIRE_REPO_DIR RAGONFIRE_DATA_DIR
  export INPUT_DIR OUTPUT_DIR WORKING_DIR BACKUPS_DIR OLLAMA_MODELS HF_HOME
  export MINERU_MODELS_DIR PGDATA_IMG HOST_LOGS_DIR LOG_DIR RF_OS RF_OLLAMA_URL
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

# Single seam for reaching the Postgres container: owns the container name, the
# docker-exec transport, and standard auth (-U/-d). Pass -i as the first arg for
# stdin-driven commands. Every rf_pg_* client below adds only its own flags, so a
# change to the container or credentials lives here alone.
# usage: rf_pg_run [-i] <tool> [tool-args...]
rf_pg_run() {
  rf_require_cmd docker
  if [ "${1:-}" = "-i" ]; then
    shift
    docker exec -i "$RF_PG_CONTAINER" "$1" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" "${@:2}"
  else
    docker exec "$RF_PG_CONTAINER" "$1" -U "$POSTGRES_USER" -d "$POSTGRES_DATABASE" "${@:2}"
  fi
}

rf_pg_exec() {
  rf_info "postgres: $*"
  rf_pg_run psql "$@"
}

rf_pg_query() {
  rf_pg_run psql -tAc "$1"
}

rf_pg_dump() {
  rf_pg_run pg_dump --format=plain
}

# Replay SQL piped on stdin with ON_ERROR_STOP (used for restore reset + replay).
rf_pg_psql_stdin() {
  rf_pg_run -i psql -v ON_ERROR_STOP=1
}

rf_pg_isready() {
  rf_pg_run pg_isready
}

rf_pg_running() {
  rf_require_cmd docker
  docker ps --format '{{.Names}}' | grep -q "^${RF_PG_CONTAINER}$"
}

# Run an e2fsprogs command against the loopback image in a throwaway container.
# Centralizes the alpine + e2fsprogs install shared by db-init and db-grow.
# usage: rf_ext4_helper "<shell command operating on /img>"
rf_ext4_helper() {
  rf_require_cmd docker
  MSYS_NO_PATHCONV=1 rf_run docker run --rm -v "$PGDATA_IMG:/img" alpine:3.20 sh -c \
    "apk add --no-cache --quiet e2fsprogs >/dev/null && $1"
}

rf_latest_snapshot() {
  find "$BACKUPS_DIR" -maxdepth 1 -name 'pgdump-*.sql.gz' -type f -print 2>/dev/null | sort -r | head -1 || true
}

# Assert a snapshot path is a non-empty, valid gzip before trusting it as the
# rollback point ahead of a destructive operation (logs to stdout/stderr; the
# path must be captured separately via rf_latest_snapshot to stay capture-safe).
rf_verify_snapshot() {
  local snapshot="$1"
  [ -n "$snapshot" ] || rf_die "snapshot was not created; refusing to continue"
  [ -s "$snapshot" ] || rf_die "snapshot is empty: $snapshot"
  rf_run gzip -t "$snapshot"
  rf_info "verified snapshot: $snapshot"
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

rf_docker_daemon_up() {
  docker info >/dev/null 2>&1
}

rf_docker_launch_desktop() {
  case "${RF_OS:-}" in
    darwin)
      rf_run open -a Docker
      ;;
    windows)
      rf_run powershell -NoProfile -Command \
        "Start-Process -FilePath \$Env:ProgramFiles'\Docker\Docker\Docker Desktop.exe'"
      ;;
    linux|wsl)
      # No Desktop GUI; try the systemd service if present.
      if command -v systemctl >/dev/null 2>&1; then
        rf_run sudo systemctl start docker || return 1
      else
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

# Ensure the docker daemon is reachable, auto-launching it if not. Avoids the
# "Cannot connect to the Docker daemon" failure when Docker Desktop is closed.
rf_ensure_docker_running() {
  rf_require_cmd docker
  if rf_docker_daemon_up; then
    return 0
  fi
  rf_info "docker daemon not reachable; attempting to start it"
  if ! rf_docker_launch_desktop; then
    rf_die "could not auto-start docker for OS '${RF_OS:-unknown}'. Start Docker manually, then retry."
  fi
  local attempts="${1:-60}" sleep_seconds="${2:-2}" i
  rf_info "waiting for docker daemon (up to $((attempts * sleep_seconds))s)"
  for i in $(seq 1 "$attempts"); do
    if rf_docker_daemon_up; then
      rf_info "docker daemon ready after attempt $i/$attempts"
      return 0
    fi
    sleep "$sleep_seconds"
  done
  rf_die "docker daemon did not become ready. Check Docker Desktop, then retry."
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
