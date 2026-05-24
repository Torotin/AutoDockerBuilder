#!/usr/bin/env bash
set -Eeuo pipefail

telemt_pid=""
telemt_panel_pid=""

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

telemt /etc/telemt/config.toml &
telemt_pid="$!"

telemt-panel --config /etc/telemt-panel/config.toml &
telemt_panel_pid="$!"

set +e
wait -n "${telemt_pid}" "${telemt_panel_pid}"
exit_code="$?"
set -e

terminate_processes "${exit_code}"
