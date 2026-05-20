#!/usr/bin/env bash
# Clean stop + sync + eject the drive so it's safe to unplug.
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/ragonfire.sh"
rf_init eject
rf_load_env
rf_require_runtime_env
rf_require_cmd sync

if [ -n "${RAGONFIRE_DRIVE_ROOT:-}" ]; then
  DRIVE_ROOT="$RAGONFIRE_DRIVE_ROOT"
elif [[ "$RAGONFIRE_DATA_DIR" == /Volumes/* ]]; then
  DRIVE_ROOT="/Volumes/$(printf '%s\n' "$RAGONFIRE_DATA_DIR" | cut -d/ -f3)"
else
  DRIVE_ROOT="$(cd "$RAGONFIRE_DATA_DIR/.." && pwd)"
fi

rf_confirm_destructive "eject-drive" "stop stack, sync, and eject $DRIVE_ROOT"
rf_info "stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

rf_info "sync"
sync

OS=$("$REPO_DIR/infra/os/detect.sh")
case "$OS" in
  darwin) diskutil eject "$DRIVE_ROOT" ;;
  linux|wsl)
    DEV=$(findmnt -no SOURCE "$DRIVE_ROOT" || true)
    [ -n "$DEV" ] && udisksctl unmount -b "$DEV" && udisksctl power-off -b "$DEV" \
      || echo "[eject] manual unmount required: umount $DRIVE_ROOT" ;;
esac

rf_info "safe to unplug $DRIVE_ROOT"
