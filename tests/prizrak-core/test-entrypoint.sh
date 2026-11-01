#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/prizrak-core/DockerEntrypoint.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

make_stub() {
  destination="$1"
  shift
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' "$@"
  } >"${destination}"
  chmod +x "${destination}"
}

wait_for_file() {
  file="$1"
  for _ in $(seq 1 100); do
    [ -f "${file}" ] && return 0
    sleep 0.02
  done
  return 1
}

wait_for_count() {
  file="$1"
  want="$2"
  for _ in $(seq 1 150); do
    if [ -f "${file}" ] && [ "$(wc -l <"${file}")" -ge "${want}" ]; then
      return 0
    fi
    sleep 0.02
  done
  return 1
}

wait_for_entrypoint() {
  entrypoint_pid="$1"
  set +e
  wait "${entrypoint_pid}"
  exit_code="$?"
  set -e
  [ "${exit_code}" -eq 143 ] || fail "SIGTERM returned ${exit_code}, expected 143"
}

start_entrypoint() {
  state="$1"
  shift
  STATE="${state}" \
    PRIZRAK_BIN="${state}/bin/prizrak-core" \
    PRIZRAK_CONFIG_DIR="${state}/config" \
    PRIZRAK_PID_FILE="${state}/prizrak-core.pid" \
    PRIZRAK_GEO_SEED_DIR="${PRIZRAK_GEO_SEED_DIR:-}" \
    PRIZRAK_UPDATE_SCRIPT="${state}/update-core.sh" \
    PRIZRAK_UPDATE_INTERVAL="${PRIZRAK_UPDATE_INTERVAL:-1h}" \
    bash "${SCRIPT}" "$@" >"${state}/entrypoint.out" 2>&1 &
  ENTRYPOINT_PID="$!"
}

setup_state() {
  state="$(mktemp -d "${TMPDIR:-/tmp}/prizrak-entrypoint.XXXXXX")"
  mkdir -p "${state}/bin" "${state}/config"
  make_stub "${state}/update-core.sh" 'exit 0'
  unset PRIZRAK_GEO_SEED_DIR
  printf '%s\n' "${state}"
}

expect_entrypoint_exit() {
  entrypoint_pid="$1"
  want="$2"
  (
    sleep 2
    kill -TERM "${entrypoint_pid}" 2>/dev/null || true
  ) &
  timer_pid="$!"
  set +e
  wait "${entrypoint_pid}"
  exit_code="$?"
  set -e
  kill -TERM "${timer_pid}" 2>/dev/null || true
  wait "${timer_pid}" 2>/dev/null || true
  [ "${exit_code}" -eq "${want}" ] || fail "entrypoint exit ${exit_code}, expected ${want}"
}

test_starts_core_with_config_and_args() {
  state="$(setup_state)"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'printf "%s\n" "$@" >"${STATE}/core.args"' \
    'echo "$$" >"${STATE}/core.pid"' \
    'touch "${STATE}/core.started"' \
    'trap "touch \"${STATE}/core.terminated\"; exit 0" TERM INT' \
    'while :; do sleep 0.1; done'

  PRIZRAK_UPDATE_INTERVAL=9999 start_entrypoint "${state}" --mode test
  entrypoint_pid="${ENTRYPOINT_PID}"
  wait_for_file "${state}/core.started" || fail "core did not start"
  grep -Fqx -- "-d" "${state}/core.args" || fail "core did not receive -d flag"
  grep -Fqx -- "${state}/config" "${state}/core.args" || fail "core did not receive config dir"
  grep -Fqx -- "--mode" "${state}/core.args" || fail "core did not receive passthrough flag"
  grep -Fqx -- "test" "${state}/core.args" || fail "core did not receive passthrough value"
  [ "$(cat "${state}/prizrak-core.pid")" = "$(cat "${state}/core.pid")" ] ||
    fail "pid file did not contain child pid"

  kill -TERM "${entrypoint_pid}"
  wait_for_entrypoint "${entrypoint_pid}"
  wait_for_file "${state}/core.terminated" || fail "SIGTERM was not forwarded to core"
  rm -rf "${state}"
}

test_sigterm_stops_supervisor() {
  state="$(setup_state)"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'touch "${STATE}/core.started"' \
    'trap "touch \"${STATE}/core.terminated\"; exit 0" TERM INT' \
    'while :; do sleep 0.1; done'

  PRIZRAK_UPDATE_INTERVAL=9999 start_entrypoint "${state}"
  entrypoint_pid="${ENTRYPOINT_PID}"
  wait_for_file "${state}/core.started" || fail "core did not start before SIGTERM test"

  kill -TERM "${entrypoint_pid}"
  wait_for_entrypoint "${entrypoint_pid}"
  wait_for_file "${state}/core.terminated" || fail "core did not receive SIGTERM"
  rm -rf "${state}"
}

test_update_restart_command_restarts_core() {
  state="$(setup_state)"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'echo "$$" >>"${STATE}/core.pids"' \
    'touch "${STATE}/core.started"' \
    'trap "touch \"${STATE}/core.terminated.$$\"; exit 0" TERM INT' \
    'while :; do sleep 0.1; done'
  # shellcheck disable=SC2016
  make_stub "${state}/update-core.sh" \
    'touch "${STATE}/updater.called"' \
    'if [ ! -f "${STATE}/restart.done" ]; then' \
    '  touch "${STATE}/restart.done"' \
    '  eval "${PRIZRAK_RESTART_CMD}"' \
    'fi'

  PRIZRAK_UPDATE_INTERVAL=1s start_entrypoint "${state}"
  entrypoint_pid="${ENTRYPOINT_PID}"
  wait_for_file "${state}/core.started" || fail "core did not start before restart test"
  wait_for_file "${state}/updater.called" || fail "updater was not called"
  wait_for_count "${state}/core.pids" 2 || fail "core was not restarted after update restart command"

  first_pid="$(sed -n '1p' "${state}/core.pids")"
  second_pid="$(sed -n '2p' "${state}/core.pids")"
  [ "${first_pid}" != "${second_pid}" ] || fail "restart reused the same child pid"
  [ -f "${state}/core.terminated.${first_pid}" ] || fail "restart command did not terminate first child"

  kill -TERM "${entrypoint_pid}"
  wait_for_entrypoint "${entrypoint_pid}"
  rm -rf "${state}"
}

test_clean_exit_is_not_restarted() {
  state="$(setup_state)"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'echo "$$" >>"${STATE}/core.pids"' \
    'exit 0'

  PRIZRAK_UPDATE_INTERVAL=9999 start_entrypoint "${state}" -v
  entrypoint_pid="${ENTRYPOINT_PID}"
  expect_entrypoint_exit "${entrypoint_pid}" 0
  [ -f "${state}/core.pids" ] || fail "core did not run"
  [ "$(wc -l <"${state}/core.pids")" -eq 1 ] || fail "clean exit was restarted"
  rm -rf "${state}"
}

test_nonzero_exit_restarts_core() {
  state="$(setup_state)"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'echo "$$" >>"${STATE}/core.pids"' \
    'if [ ! -f "${STATE}/core.failed-once" ]; then touch "${STATE}/core.failed-once"; exit 1; fi' \
    'touch "${STATE}/core.started"' \
    'trap "exit 0" TERM INT' \
    'while :; do sleep 0.1; done'

  PRIZRAK_UPDATE_INTERVAL=9999 start_entrypoint "${state}"
  entrypoint_pid="${ENTRYPOINT_PID}"
  wait_for_file "${state}/core.started" || fail "core was not restarted after a non-zero exit"
  wait_for_count "${state}/core.pids" 2 || fail "non-zero exit did not start a new core"

  kill -TERM "${entrypoint_pid}"
  wait_for_entrypoint "${entrypoint_pid}"
  rm -rf "${state}"
}

test_seeds_missing_geo_without_overwrite() {
  state="$(setup_state)"
  mkdir -p "${state}/seed"
  printf 'baked-geoip' >"${state}/seed/geoip.dat"
  printf 'baked-geosite' >"${state}/seed/geosite.dat"
  printf 'baked-metadb' >"${state}/seed/geoip.metadb"
  printf 'user-geosite' >"${state}/config/geosite.dat"
  # shellcheck disable=SC2016
  make_stub "${state}/bin/prizrak-core" \
    'touch "${STATE}/core.started"' \
    'trap "exit 0" TERM INT' \
    'while :; do sleep 0.1; done'

  PRIZRAK_GEO_SEED_DIR="${state}/seed" PRIZRAK_UPDATE_INTERVAL=9999 start_entrypoint "${state}"
  entrypoint_pid="${ENTRYPOINT_PID}"
  wait_for_file "${state}/core.started" || fail "core did not start during geo seed test"
  [ "$(cat "${state}/config/geoip.dat")" = "baked-geoip" ] || fail "missing geoip.dat was not seeded"
  [ "$(cat "${state}/config/geosite.dat")" = "user-geosite" ] || fail "existing geosite.dat was overwritten"
  [ "$(cat "${state}/config/geoip.metadb")" = "baked-metadb" ] || fail "missing geoip.metadb was not seeded"

  kill -TERM "${entrypoint_pid}"
  wait_for_entrypoint "${entrypoint_pid}"
  rm -rf "${state}"
}

test_dockerfile_keeps_geo_seed_copy() {
  dockerfile="${ROOT}/bin/prizrak-core/Dockerfile"
  grep -q '/opt/prizrak/geo/' "${dockerfile}" || fail "Dockerfile does not bake /opt/prizrak/geo/"
}

test_starts_core_with_config_and_args
test_sigterm_stops_supervisor
test_update_restart_command_restarts_core
test_clean_exit_is_not_restarted
test_nonzero_exit_restarts_core
test_seeds_missing_geo_without_overwrite
test_dockerfile_keeps_geo_seed_copy
printf 'OK test-entrypoint\n'
