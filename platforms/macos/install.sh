#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 <repo-path> [options]

Options:
  --label LABEL      launchd label (default: com.git-autosync.<repo-name>)
  --interval SECS    sync interval in seconds (default: 300)
  --log PATH         log file path (default: ~/Library/Logs/<label>.log)
  --python PATH      python3 interpreter (default: /usr/bin/python3)
  -h, --help         show this help
EOF
}

REPO_PATH=""
LABEL=""
INTERVAL=300
LOG_PATH=""
PYTHON="/usr/bin/python3"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --label)    LABEL="$2";    shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --log)      LOG_PATH="$2"; shift 2 ;;
        --python)   PYTHON="$2";   shift 2 ;;
        -*)         echo "Unknown option: $1"; usage; exit 1 ;;
        *)          REPO_PATH="$1"; shift ;;
    esac
done

if [[ -z "$REPO_PATH" ]]; then
    echo "error: repo path is required"
    usage
    exit 1
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
REPO_NAME="$(basename "$REPO_PATH")"

[[ -z "$LABEL" ]]    && LABEL="com.git-autosync.${REPO_NAME}"
[[ -z "$LOG_PATH" ]] && LOG_PATH="${HOME}/Library/Logs/${LABEL}.log"

SCRIPT_PATH="${REPO_ROOT}/sync.py"
PLIST_DEST="${HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ ! -f "$PYTHON" ]]; then
    echo "error: python3 not found at ${PYTHON}"
    exit 1
fi

if [[ ! -d "${REPO_PATH}/.git" ]]; then
    echo "error: ${REPO_PATH} is not a git repository"
    exit 1
fi

echo "Configuring git-autosync:"
echo "  Repo:     ${REPO_PATH}"
echo "  Label:    ${LABEL}"
echo "  Interval: ${INTERVAL}s"
echo "  Log:      ${LOG_PATH}"
echo "  Plist:    ${PLIST_DEST}"

sed \
    -e "s|{{LABEL}}|${LABEL}|g" \
    -e "s|{{SCRIPT_PATH}}|${SCRIPT_PATH}|g" \
    -e "s|{{REPO_PATH}}|${REPO_PATH}|g" \
    -e "s|{{INTERVAL}}|${INTERVAL}|g" \
    -e "s|{{HOME}}|${HOME}|g" \
    -e "s|{{LOG_PATH}}|${LOG_PATH}|g" \
    -e "s|{{PYTHON}}|${PYTHON}|g" \
    "${SCRIPT_DIR}/launchd.plist.template" > "${PLIST_DEST}"



# Unload existing agent if already registered
if launchctl list "${LABEL}" &>/dev/null 2>&1; then
    echo "Unloading existing ${LABEL}..."
    launchctl unload "${PLIST_DEST}" 2>/dev/null || true
fi

chmod +x "${SCRIPT_PATH}"
launchctl load "${PLIST_DEST}"
echo "Done. Logs: tail -f ${LOG_PATH}"
