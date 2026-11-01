#!/bin/sh
set -eu

SCRIPT_DIR=$(dirname -- "$0")
SCRIPT_DIR=$(cd -- "${SCRIPT_DIR}" && pwd)

PRIZRAK_BIN="${PRIZRAK_BIN:-/opt/prizrak/prizrak-core}"
PRIZRAK_CONFIG_DIR="${PRIZRAK_CONFIG_DIR:-/root/.config/mihomo}"
PRIZRAK_PID_FILE="${PRIZRAK_PID_FILE:-/temp/prizrak-core.pid}"
PRIZRAK_RESTART_REQUEST="${PRIZRAK_PID_FILE}.restart"
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

seed_missing_geo() {
  seed_dir="${PRIZRAK_GEO_SEED_DIR:-/opt/prizrak/geo}"
  [ -d "${seed_dir}" ] || return 0
  mkdir -p "${PRIZRAK_CONFIG_DIR}"
  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    if [ -f "${seed_dir}/${geo_asset}" ] && [ ! -e "${PRIZRAK_CONFIG_DIR}/${geo_asset}" ]; then
      cp -f "${seed_dir}/${geo_asset}" "${PRIZRAK_CONFIG_DIR}/${geo_asset}"
    fi
  done
}

stop_update_loop() {
  if [ -z "${update_pid}" ]; then
    return 0
  fi
  if kill -0 "${update_pid}" 2>/dev/null; then
    ps -eo pid=,ppid= 2>/dev/null | while read -r pid ppid; do
      if [ "${ppid}" = "${update_pid}" ]; then
        kill -TERM "${pid}" 2>/dev/null || true
      fi
    done
    kill -TERM "${update_pid}" 2>/dev/null || true
  fi
  wait "${update_pid}" 2>/dev/null || true
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

  stop_update_loop

  if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
    kill -TERM "${child_pid}" 2>/dev/null || true
  fi

  if [ -n "${child_pid}" ]; then
    wait "${child_pid}" 2>/dev/null || true
  fi

  exit 143
}

update_loop() {
  interval="$(prizrak_interval_seconds "${PRIZRAK_UPDATE_INTERVAL}")"
  # A graceful core exits 0. Record the request first so the supervisor still
  # starts the new binary. A spontaneous exit 0, such as "prizrak-core -v", has no request.
  restart_cmd="touch \"${PRIZRAK_RESTART_REQUEST}\"; [ ! -f \"${PRIZRAK_PID_FILE}\" ] || kill -TERM \$(cat \"${PRIZRAK_PID_FILE}\")"

  while :; do
    sleep "${interval}"
    PRIZRAK_RESTART_CMD="${restart_cmd}" "${PRIZRAK_UPDATE_SCRIPT}" || true
  done
}

trap terminate TERM INT

seed_missing_geo
start_core "$@"
update_loop &
update_pid="$!"

while :; do
  set +e
  wait "${child_pid}"
  exit_code="$?"
  set -e

  if [ "${shutting_down}" -ne 0 ]; then
    exit "${exit_code}"
  fi
  if [ -f "${PRIZRAK_RESTART_REQUEST}" ]; then
    rm -f "${PRIZRAK_RESTART_REQUEST}"
    log "core restart requested"
    start_core "$@"
    continue
  fi
  if [ "${exit_code}" -eq 0 ]; then
    log "core exited cleanly"
    shutting_down=1
    stop_update_loop
    exit 0
  fi
  log "core exited with ${exit_code}; restarting"
  start_core "$@"
done
