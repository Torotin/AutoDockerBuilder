#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HC="${ROOT}/bin/prizrak-core/healthcheck.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_hc() {
  state="$1"
  shift
  set +e
  env \
    PRIZRAK_PID_FILE="${state}/prizrak-core.pid" \
    PRIZRAK_LOCK_FILE="${state}/prizrak-update.lock" \
    PRIZRAK_RESTART_REQUEST="${state}/prizrak-core.pid.restart" \
    PRIZRAK_HC_GRACE_SEC=1 \
    "$@" \
    sh "${HC}"
  rc=$?
  set -e
  return "${rc}"
}

test_live_pid_is_healthy() {
  state="$(mktemp -d)"
  # shellcheck disable=SC2016
  sleep 30 &
  live_pid=$!
  printf '%s\n' "${live_pid}" >"${state}/prizrak-core.pid"
  if ! run_hc "${state}"; then
    kill "${live_pid}" 2>/dev/null || true
    wait "${live_pid}" 2>/dev/null || true
    rm -rf "${state}"
    fail "live pid should be healthy"
  fi
  kill "${live_pid}" 2>/dev/null || true
  wait "${live_pid}" 2>/dev/null || true
  rm -rf "${state}"
}

test_dead_pid_is_unhealthy() {
  state="$(mktemp -d)"
  printf '999999\n' >"${state}/prizrak-core.pid"
  if run_hc "${state}"; then
    rm -rf "${state}"
    fail "dead pid should be unhealthy"
  fi
  rm -rf "${state}"
}

test_restart_marker_is_healthy() {
  state="$(mktemp -d)"
  printf '999999\n' >"${state}/prizrak-core.pid"
  touch "${state}/prizrak-core.pid.restart"
  if ! run_hc "${state}"; then
    rm -rf "${state}"
    fail "restart marker should keep healthcheck green"
  fi
  rm -rf "${state}"
}

test_update_lock_is_healthy() {
  state="$(mktemp -d)"
  printf '999999\n' >"${state}/prizrak-core.pid"
  mkdir "${state}/prizrak-update.lock"
  if ! run_hc "${state}"; then
    rm -rf "${state}"
    fail "update lock should keep healthcheck green"
  fi
  rm -rf "${state}"
}

test_live_pid_is_healthy
test_dead_pid_is_unhealthy
test_restart_marker_is_healthy
test_update_lock_is_healthy
printf 'OK test-healthcheck\n'
