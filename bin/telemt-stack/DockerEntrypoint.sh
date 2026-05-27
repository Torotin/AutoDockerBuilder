#!/usr/bin/env bash
set -Eeuo pipefail

: "${TELEMT_PANEL_ENABLED:=true}"

telemt_pid=""
telemt_panel_pid=""

log() {
    printf '[telemt-stack] %s\n' "$*" >&2
}

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

terminate_processes() {
    exit_code="${1:-143}"
    trap - TERM INT

    if [ -n "${telemt_pid}" ] && kill -0 "${telemt_pid}" 2>/dev/null; then
        kill -TERM "${telemt_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_panel_pid}" ] && kill -0 "${telemt_panel_pid}" 2>/dev/null; then
        kill -TERM "${telemt_panel_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_pid}" ]; then
        wait "${telemt_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_panel_pid}" ]; then
        wait "${telemt_panel_pid}" 2>/dev/null || true
    fi

    exit "${exit_code}"
}

trap 'terminate_processes 143' TERM INT

log "starting telemt"
telemt /etc/telemt/config.toml &
telemt_pid="$!"

set +e
if is_true "${TELEMT_PANEL_ENABLED}"; then
    log "starting bundled telemt-panel"
    telemt-panel --config /etc/telemt-panel/config.toml &
    telemt_panel_pid="$!"
    wait -n "${telemt_pid}" "${telemt_panel_pid}"
else
    log "bundled telemt-panel disabled; waiting for telemt only"
    wait "${telemt_pid}"
fi
exit_code="$?"
set -e

terminate_processes "${exit_code}"
