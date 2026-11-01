#!/bin/sh
# Docker HEALTHCHECK helper for prizrak-core.
# Treats an in-flight update/restart as healthy so compose does not flap
# while the supervisor replaces the child process.
set -eu

PRIZRAK_PID_FILE="${PRIZRAK_PID_FILE:-/temp/prizrak-core.pid}"
PRIZRAK_LOCK_FILE="${PRIZRAK_LOCK_FILE:-/temp/prizrak-update.lock}"
PRIZRAK_RESTART_REQUEST="${PRIZRAK_RESTART_REQUEST:-${PRIZRAK_PID_FILE}.restart}"
PRIZRAK_HC_GRACE_SEC="${PRIZRAK_HC_GRACE_SEC:-4}"

pid_is_alive() {
  pid="$1"
  case "${pid}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "${pid}" 2>/dev/null
}

read_pid() {
  [ -f "${PRIZRAK_PID_FILE}" ] || return 1
  sed -n '1{s/[[:space:]]*$//;p;q;}' "${PRIZRAK_PID_FILE}"
}

update_in_flight() {
  [ -d "${PRIZRAK_LOCK_FILE}" ] || [ -e "${PRIZRAK_RESTART_REQUEST}" ]
}

# Prefer a live core. Brief wait covers hard-restart race inside HEALTHCHECK timeout.
attempts=$((PRIZRAK_HC_GRACE_SEC * 5))
if [ "${attempts}" -lt 1 ]; then
  attempts=1
fi

i=0
while [ "${i}" -lt "${attempts}" ]; do
  if pid="$(read_pid 2>/dev/null)" && pid_is_alive "${pid}"; then
    exit 0
  fi
  # Update owns the process: lock and/or restart marker mean "don't fail yet".
  if update_in_flight; then
    exit 0
  fi
  i=$((i + 1))
  sleep 0.2
done

# Last chance: marker appeared during the wait loop.
if update_in_flight; then
  exit 0
fi

exit 1
