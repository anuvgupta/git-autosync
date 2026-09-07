#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

usage() {
    cat <<EOF
Usage: $0 <repo-path> [options]

Options:
  --backend {cron|systemd}   scheduler to use (default: cron)
  --label LABEL              scheduler unit label
                             cron default:    git-autosync-<repo-name>
                             systemd default: git-autosync-<repo-name>
  --interval SECS            sync interval in seconds (default: 300)
                             cron: must be a multiple of 60; a clean divisor of
                             60 (60/120/180/300/600/900/1800/3600) is enforced
  --log PATH                 log file path
                             (default: ~/.local/state/git-autosync/<label>.log)
  --python PATH              python3 interpreter (default: \$(command -v python3))
  -h, --help                 show this help
EOF
}

REPO_PATH=""
LABEL=""
INTERVAL=300
LOG_PATH=""
PYTHON=""
BACKEND="cron"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --backend)  BACKEND="$2";  shift 2 ;;
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

case "$BACKEND" in
    cron|systemd) ;;
    *) echo "error: --backend must be 'cron' or 'systemd', got '$BACKEND'"; exit 1 ;;
esac

[[ -z "$PYTHON" ]] && PYTHON="$(command -v python3 || true)"
if [[ -z "$PYTHON" || ! -x "$PYTHON" ]]; then
    echo "error: python3 not found (pass --python)"
    exit 1
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
REPO_NAME="$(basename "$REPO_PATH")"

if [[ ! -d "${REPO_PATH}/.git" ]]; then
    echo "error: ${REPO_PATH} is not a git repository"
    exit 1
fi

[[ -z "$LABEL" ]]    && LABEL="git-autosync-${REPO_NAME}"
[[ -z "$LOG_PATH" ]] && LOG_PATH="${HOME}/.local/state/git-autosync/${LABEL}.log"

SCRIPT_PATH="${REPO_ROOT}/sync.py"
chmod +x "$SCRIPT_PATH"
mkdir -p "$(dirname "$LOG_PATH")"

install_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "error: crontab not found; install cron (e.g. 'sudo apt install cron') or use --backend systemd"
        exit 1
    fi

    if (( INTERVAL < 60 )); then
        echo "error: cron granularity is 1 minute; --interval must be >= 60"
        exit 1
    fi
    if (( INTERVAL % 60 != 0 )); then
        echo "error: cron requires --interval to be a multiple of 60 (got ${INTERVAL})"
        exit 1
    fi

    local mins=$(( INTERVAL / 60 ))
    local cron_expr
    case "$mins" in
        1)  cron_expr="* * * * *" ;;
        2|3|4|5|6|10|12|15|20|30)
            cron_expr="*/${mins} * * * *" ;;
        60)
            cron_expr="0 * * * *" ;;
        *)
            # not a clean divisor of 60 — cron */N wraps at the hour boundary
            echo "error: cron */N only fires cleanly for N that divides 60 (2,3,4,5,6,10,12,15,20,30)"
            echo "       got ${mins} minutes; pick a clean interval or use --backend systemd"
            exit 1 ;;
    esac

    local marker="# git-autosync:${LABEL}"
    local line="${cron_expr} ${PYTHON} ${SCRIPT_PATH} ${REPO_PATH} >> ${LOG_PATH} 2>&1 ${marker}"

    echo "Configuring git-autosync (cron):"
    echo "  Repo:     ${REPO_PATH}"
    echo "  Label:    ${LABEL}"
    echo "  Cron:     ${cron_expr}  (every ${mins} min)"
    echo "  Log:      ${LOG_PATH}"

    # rewrite crontab: strip any existing line with this marker, append the new one
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    { printf '%s\n' "$existing" | grep -v -F "$marker" || true; printf '%s\n' "$line"; } | crontab -

    echo "Done. Verify: crontab -l | grep ${LABEL}"
    echo "Logs:        tail -f ${LOG_PATH}"
    echo
    echo "Note: cron uses a minimal environment. If 'git push' relies on ssh-agent,"
    echo "      the job may fail — use a passphraseless SSH deploy key or a"
    echo "      credential helper that doesn't need a live agent."
}

install_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "error: systemctl not found; this backend requires systemd (use --backend cron instead)"
        exit 1
    fi

    local unit_dir="${HOME}/.config/systemd/user"
    local service_dest="${unit_dir}/${LABEL}.service"
    local timer_dest="${unit_dir}/${LABEL}.timer"

    mkdir -p "$unit_dir"

    echo "Configuring git-autosync (systemd):"
    echo "  Repo:     ${REPO_PATH}"
    echo "  Label:    ${LABEL}"
    echo "  Interval: ${INTERVAL}s"
    echo "  Log:      ${LOG_PATH}"
    echo "  Service:  ${service_dest}"
    echo "  Timer:    ${timer_dest}"

    local render_sed=(
        -e "s|{{LABEL}}|${LABEL}|g"
        -e "s|{{SCRIPT_PATH}}|${SCRIPT_PATH}|g"
        -e "s|{{REPO_PATH}}|${REPO_PATH}|g"
        -e "s|{{INTERVAL}}|${INTERVAL}|g"
        -e "s|{{LOG_PATH}}|${LOG_PATH}|g"
        -e "s|{{PYTHON}}|${PYTHON}|g"
    )
    sed "${render_sed[@]}" "${SCRIPT_DIR}/systemd.service.template" > "$service_dest"
    sed "${render_sed[@]}" "${SCRIPT_DIR}/systemd.timer.template"   > "$timer_dest"

    systemctl --user daemon-reload
    systemctl --user enable --now "${LABEL}.timer"

    echo "Done. Status: systemctl --user status ${LABEL}.timer"
    echo "Logs:        tail -f ${LOG_PATH}"
    echo
    echo "Note: on desktops without lingering enabled, timers stop when you log out."
    echo "      To keep it running headless: sudo loginctl enable-linger \$USER"
}

case "$BACKEND" in
    cron)    install_cron    ;;
    systemd) install_systemd ;;
esac
