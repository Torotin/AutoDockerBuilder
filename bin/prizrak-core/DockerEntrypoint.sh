#!/bin/sh
set -eu

SCRIPT_DIR=$(dirname -- "$0")
SCRIPT_DIR=$(cd -- "${SCRIPT_DIR}" && pwd)

PRIZRAK_BIN="${PRIZRAK_BIN:-/opt/prizrak/prizrak-core}"
PRIZRAK_CONFIG_DIR="${PRIZRAK_CONFIG_DIR:-/root/.config/mihomo}"
PRIZRAK_PID_FILE="${PRIZRAK_PID_FILE:-/temp/prizrak-core.pid}"
PRIZRAK_UPDATE_SCRIPT="${PRIZRAK_UPDATE_SCRIPT:-${SCRIPT_DIR}/update-core.sh}"
PRIZRAK_UPDATE_INTERVAL="${PRIZRAK_UPDATE_INTERVAL:-1h}"

child_pid=""
update_pid=""
shutting_down=0

log() {
  printf '[prizrak-core] %s\n' "$*" >&2
}

prizrak_interval_seconds() {
  value="${1:-1h}"
  case "${value}" in
    *h) echo $((${value%h} * 3600)) ;;
    *m) echo $((${value%m} * 60)) ;;
    *s) echo "${value%s}" ;;
    *) echo "${value}" ;;
  esac
}

start_core() {
  mkdir -p "$(dirname "${PRIZRAK_PID_FILE}")"
  log "starting core"
  "${PRIZRAK_BIN}" -d "${PRIZRAK_CONFIG_DIR}" "$@" &
  child_pid="$!"
  printf '%s\n' "${child_pid}" >"${PRIZRAK_PID_FILE}"
}

terminate() {
  shutting_down=1
  trap - TERM INT

  if [ -n "${update_pid}" ] && kill -0 "${update_pid}" 2>/dev/null; then
    kill -TERM "${update_pid}" 2>/dev/null || true
  fi

  if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
    kill -TERM "${child_pid}" 2>/dev/null || true
  fi

  if [ -n "${child_pid}" ]; then
    wait "${child_pid}" 2>/dev/null || true
  fi
  if [ -n "${update_pid}" ]; then
    wait "${update_pid}" 2>/dev/null || true
  fi

  exit 143
}

update_loop() {
  interval="$(prizrak_interval_seconds "${PRIZRAK_UPDATE_INTERVAL}")"
  restart_cmd="[ ! -f \"${PRIZRAK_PID_FILE}\" ] || kill -TERM \$(cat \"${PRIZRAK_PID_FILE}\")"

  while :; do
    sleep "${interval}"
    PRIZRAK_RESTART_CMD="${restart_cmd}" "${PRIZRAK_UPDATE_SCRIPT}" || true
  done
}

trap terminate TERM INT

start_core "$@"
update_loop &
update_pid="$!"

while :; do
  set +e
  wait "${child_pid}"
  exit_code="$?"
  set -e

  [ "${shutting_down}" -eq 0 ] || exit "${exit_code}"
  log "core exited with ${exit_code}; restarting"
  start_core "$@"
done
