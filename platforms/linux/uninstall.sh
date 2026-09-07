#!/usr/bin/env bash
# Removes cron and/or systemd entries for the given label (or repo path).
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 <label-or-repo-path>

  label-or-repo-path   The scheduler label (e.g. git-autosync-myrepo)
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
    LABEL="git-autosync-${REPO_NAME}"
else
    LABEL="$ARG"
fi

removed_any=false

# cron
if command -v crontab >/dev/null 2>&1; then
    marker="# git-autosync:${LABEL}"
    existing="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$existing" | grep -qF "$marker"; then
        printf '%s\n' "$existing" | grep -v -F "$marker" | crontab -
        echo "Removed cron entry for ${LABEL}"
        removed_any=true
    fi
fi

# systemd user
unit_dir="${HOME}/.config/systemd/user"
service="${unit_dir}/${LABEL}.service"
timer="${unit_dir}/${LABEL}.timer"
if [[ -f "$service" || -f "$timer" ]]; then
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now "${LABEL}.timer" 2>/dev/null || true
        systemctl --user stop "${LABEL}.service" 2>/dev/null || true
    fi
    rm -f "$service" "$timer"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload
    fi
    echo "Removed systemd units for ${LABEL}"
    removed_any=true
fi

if [[ "$removed_any" != true ]]; then
    echo "Nothing found to remove for ${LABEL}"
    exit 1
fi
