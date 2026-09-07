#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <label-or-repo-path>

  label-or-repo-path   The launchd label (e.g. com.git-autosync.myrepo)
                       or the repo path that was passed to install.sh
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

ARG="$1"

if [[ "$ARG" == */* || "$ARG" == "." || "$ARG" == ".." ]]; then
    REPO_NAME="$(basename "$(cd "$ARG" && pwd)")"
    LABEL="com.git-autosync.${REPO_NAME}"
else
    LABEL="$ARG"
fi

PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ ! -f "$PLIST" ]]; then
    echo "No plist found at ${PLIST}"
    exit 1
fi

launchctl unload "$PLIST"
rm "$PLIST"
echo "Uninstalled ${LABEL}"
