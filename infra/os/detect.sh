#!/usr/bin/env bash
# Echoes "darwin", "linux", or "wsl".
set -euo pipefail
uname_s=$(uname -s)
case "$uname_s" in
  Darwin) echo darwin ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl
    else echo linux; fi ;;
  *) echo "unsupported: $uname_s" >&2; exit 1 ;;
esac
