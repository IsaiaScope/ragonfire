#!/usr/bin/env bash
# Clean stop + sync + eject the drive so it's safe to unplug.
set -euo pipefail
# shellcheck disable=SC1090
set -a; source "${RAGONFIRE_RUNTIME:-$HOME/rag-anything}/.env"; set +a
REPO_DIR="${RAGONFIRE_REPO_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )}"

DRIVE_ROOT="/Volumes/Crucial-4T"

echo "[eject] stopping stack"
"$REPO_DIR/rag-anything/scripts/lightrag-stop.sh"

echo "[eject] sync"
sync

OS=$("$REPO_DIR/infra/os/detect.sh")
case "$OS" in
  darwin) diskutil eject "$DRIVE_ROOT" ;;
  linux|wsl)
    DEV=$(findmnt -no SOURCE "$DRIVE_ROOT" || true)
    [ -n "$DEV" ] && udisksctl unmount -b "$DEV" && udisksctl power-off -b "$DEV" \
      || echo "[eject] manual unmount required: umount $DRIVE_ROOT" ;;
esac

echo "[eject] safe to unplug Crucial-4T"
