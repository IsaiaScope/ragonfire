#!/usr/bin/env bash
# Echoes "darwin", "linux", "wsl", or "windows".
set -euo pipefail

if [ -n "${RF_OS_OVERRIDE:-}" ]; then
  echo "$RF_OS_OVERRIDE"
  exit 0
fi

uname_s=$(uname -s)
case "$uname_s" in
  Darwin) echo darwin ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
    else echo linux; fi ;;
  MINGW*|MSYS*|CYGWIN*) echo windows ;;
  *) echo "unsupported: $uname_s" >&2; exit 1 ;;
esac
