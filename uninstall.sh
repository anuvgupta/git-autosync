#!/usr/bin/env bash
# Dispatches to the platform-specific uninstaller under platforms/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$(uname -s)" in
    Darwin) exec "${SCRIPT_DIR}/platforms/macos/uninstall.sh" "$@" ;;
    Linux)  exec "${SCRIPT_DIR}/platforms/linux/uninstall.sh" "$@" ;;
    *)
        echo "error: unsupported platform: $(uname -s)" >&2
        exit 1
        ;;
esac
