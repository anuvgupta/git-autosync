#!/usr/bin/env bash
# Dispatches to the platform-specific installer under platforms/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) exec "${SCRIPT_DIR}/platforms/macos/install.sh" "$@" ;;
    Linux)  exec "${SCRIPT_DIR}/platforms/linux/install.sh" "$@" ;;
    MINGW*|MSYS*|CYGWIN*)
        # Git Bash / MSYS2 on Windows: hand off to PowerShell.
        exec powershell.exe -NoProfile -ExecutionPolicy Bypass \
            -File "$(cygpath -w "${SCRIPT_DIR}/platforms/windows/install.ps1")" "$@" ;;
    *)
        echo "error: unsupported platform: $(uname -s)" >&2
        echo "       see platforms/ for available implementations" >&2
        exit 1
        ;;
esac
