#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/telemt-stack/DockerEntrypoint.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

make_stub() {
    destination="$1"
    shift
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' "$@"
    } > "${destination}"
    chmod +x "${destination}"
}

run_entrypoint() {
    state="$1"
    shift
    set +e
    output="$(STATE="${state}" PATH="${state}/bin:${PATH}" "$@" bash "${SCRIPT}" 2>&1)"
    exit_code="$?"
    set -e
    printf '%s' "${output}" > "${state}/output"
    return "${exit_code}"
}

test_panel_enabled_by_default() {
    state="$(mktemp -d)"
    mkdir -p "${state}/bin"
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt" \
        'printf "%s\n" "$*" > "${STATE}/telemt.args"' \
        'while [ ! -f "${STATE}/panel.started" ]; do sleep 0.01; done' \
        'exit 17'
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt-panel" \
        'printf "%s\n" "$*" > "${STATE}/panel.args"' \
        'touch "${STATE}/panel.started"' \
        'trap "exit 0" TERM INT' \
        'while :; do sleep 1; done'

    if run_entrypoint "${state}" env; then
        fail "entrypoint did not pass telemt failure exit code"
    else
        exit_code="$?"
    fi

    [ "${exit_code}" -eq 17 ] || fail "default mode returned ${exit_code}, expected 17"
    grep -Fqx -- '/etc/telemt/config.toml' "${state}/telemt.args" ||
        fail "telemt command did not receive its config path"
    grep -Fqx -- '--config /etc/telemt-panel/config.toml' "${state}/panel.args" ||
        fail "telemt-panel command did not receive its config path"
    rm -rf "${state}"
}

test_panel_can_be_disabled() {
    state="$(mktemp -d)"
    mkdir -p "${state}/bin"
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt" \
        'touch "${STATE}/telemt.started"' \
        'sleep 0.1' \
        'exit 23'
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt-panel" \
        'touch "${STATE}/panel.started"' \
        'exit 0'

    if run_entrypoint "${state}" env TELEMT_PANEL_ENABLED=false; then
        fail "telemt-only mode did not pass telemt failure exit code"
    else
        exit_code="$?"
    fi

    [ "${exit_code}" -eq 23 ] || fail "telemt-only mode returned ${exit_code}, expected 23"
    [ -f "${state}/telemt.started" ] || fail "telemt was not started when panel was disabled"
    [ ! -e "${state}/panel.started" ] || fail "telemt-panel was started when disabled"
    rm -rf "${state}"
}

test_panel_failure_is_returned() {
    state="$(mktemp -d)"
    mkdir -p "${state}/bin"
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt" \
        'touch "${STATE}/telemt.started"' \
        'trap "exit 0" TERM INT' \
        'while :; do sleep 1; done'
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt-panel" \
        'touch "${STATE}/panel.started"' \
        'exit 29'

    if run_entrypoint "${state}" env; then
        fail "entrypoint did not pass panel failure exit code"
    else
        exit_code="$?"
    fi

    [ "${exit_code}" -eq 29 ] || fail "panel failure returned ${exit_code}, expected 29"
    rm -rf "${state}"
}

test_sigterm_in_telemt_only_mode() {
    state="$(mktemp -d)"
    mkdir -p "${state}/bin"
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt" \
        'touch "${STATE}/telemt.started"' \
        'trap "touch \"${STATE}/telemt.terminated\"; exit 0" TERM INT' \
        'while :; do sleep 0.1; done'
    # shellcheck disable=SC2016
    make_stub "${state}/bin/telemt-panel" \
        'touch "${STATE}/panel.started"' \
        'trap "touch \"${STATE}/panel.terminated\"; exit 0" TERM INT' \
        'while :; do sleep 0.1; done'

    STATE="${state}" PATH="${state}/bin:${PATH}" TELEMT_PANEL_ENABLED=false bash "${SCRIPT}" &
    entrypoint_pid="$!"
    for _ in $(seq 1 50); do
        [ -f "${state}/telemt.started" ] && break
        sleep 0.02
    done
    [ -f "${state}/telemt.started" ] || fail "telemt did not start before SIGTERM test"

    kill -TERM "${entrypoint_pid}"
    set +e
    wait "${entrypoint_pid}"
    exit_code="$?"
    set -e

    [ "${exit_code}" -eq 143 ] || fail "SIGTERM returned ${exit_code}, expected 143"
    [ -f "${state}/telemt.terminated" ] || fail "SIGTERM was not forwarded to telemt"
    [ ! -e "${state}/panel.started" ] || fail "disabled panel started during SIGTERM test"
    [ ! -e "${state}/panel.terminated" ] || fail "SIGTERM was forwarded to disabled panel"
    rm -rf "${state}"
}

test_panel_enabled_by_default
test_panel_can_be_disabled
test_panel_failure_is_returned
test_sigterm_in_telemt_only_mode
printf 'PASS: telemt-stack entrypoint behavior\n'
