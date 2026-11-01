#!/bin/sh
set -eu

# shellcheck disable=SC1091
. "$(dirname "$0")/asset-name.sh"

PRIZRAK_BIN="${PRIZRAK_BIN:-/opt/prizrak/prizrak-core}"
PRIZRAK_STATE_FILE="${PRIZRAK_STATE_FILE:-/opt/prizrak/installed-release}"
PRIZRAK_STAGE_DIR="${PRIZRAK_STAGE_DIR:-/temp/prizrak-update}"
PRIZRAK_BACKUP_DIR="${PRIZRAK_BACKUP_DIR:-/temp/prizrak-backup}"
PRIZRAK_LOCK_FILE="${PRIZRAK_LOCK_FILE:-/temp/prizrak-update.lock}"
PRIZRAK_CONFIG_DIR="${PRIZRAK_CONFIG_DIR:-/root/.config/mihomo}"
PRIZRAK_REPO="${PRIZRAK_REPO:-legiz-ru/Prizrak-Core}"
PRIZRAK_GEO_BASE_URL="${PRIZRAK_GEO_BASE_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest}"
PRIZRAK_CORE_VARIANT="${PRIZRAK_CORE_VARIANT:-v3}"
PRIZRAK_CURL="${PRIZRAK_CURL:-curl}"
PRIZRAK_PID_FILE="${PRIZRAK_PID_FILE:-/temp/prizrak-core.pid}"
PRIZRAK_HEALTH_CMD="${PRIZRAK_HEALTH_CMD:-default_health}"
PRIZRAK_HEALTH_WAIT_SEC="${PRIZRAK_HEALTH_WAIT_SEC:-15}"
PRIZRAK_HEALTH_SETTLE_SEC="${PRIZRAK_HEALTH_SETTLE_SEC:-1}"
PRIZRAK_HEALTH_PROBE_TIMEOUT="${PRIZRAK_HEALTH_PROBE_TIMEOUT:-2}"
PRIZRAK_RESTART_CMD="${PRIZRAK_RESTART_CMD:-:}"

RESTART_MODE=""
PRIZRAK_HEALTH_OLD_PID=""

STAGED_BIN="${PRIZRAK_STAGE_DIR}/prizrak-core"
STAGED_GEO_DIR="${PRIZRAK_STAGE_DIR}/geo"

cleanup_lock() {
  rm -rf "${PRIZRAK_LOCK_FILE}"
}

mkdir -p "$(dirname "${PRIZRAK_LOCK_FILE}")"
if ! mkdir "${PRIZRAK_LOCK_FILE}" 2>/dev/null; then
  exit 0
fi
trap cleanup_lock EXIT INT TERM

download_stdout() {
  url="$1"
  ${PRIZRAK_CURL} -fsSL "${url}"
}

download_file() {
  url="$1"
  out="$2"
  ${PRIZRAK_CURL} -fsSL -o "${out}" "${url}"
}

latest_tag() {
  json="$(download_stdout "https://api.github.com/repos/${PRIZRAK_REPO}/releases/latest")"
  tag="$(printf '%s\n' "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "${tag}" ] || return 1
  printf '%s\n' "${tag}"
}

current_tag() {
  if [ -f "${PRIZRAK_STATE_FILE}" ]; then
    sed -n '1{s/[[:space:]]*$//;p;q;}' "${PRIZRAK_STATE_FILE}"
  fi
}

stage_and_verify() {
  tag="$1"
  os="linux"
  arch="$(uname -m)"
  asset="$(prizrak_asset_name "${os}" "${arch}" "${PRIZRAK_CORE_VARIANT}" "${tag}")"
  release_url="https://github.com/${PRIZRAK_REPO}/releases/download/${tag}"
  core_gz="${PRIZRAK_STAGE_DIR}/${asset}"

  rm -rf "${PRIZRAK_STAGE_DIR}"
  mkdir -p "${STAGED_GEO_DIR}"

  if ! download_file "${release_url}/${asset}" "${core_gz}"; then
    rm -rf "${PRIZRAK_STAGE_DIR}"
    return 1
  fi

  if ! gzip -dc "${core_gz}" >"${STAGED_BIN}"; then
    rm -rf "${PRIZRAK_STAGE_DIR}"
    return 1
  fi
  chmod +x "${STAGED_BIN}"

  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    if ! download_file "${PRIZRAK_GEO_BASE_URL}/${geo_asset}" "${STAGED_GEO_DIR}/${geo_asset}"; then
      rm -rf "${PRIZRAK_STAGE_DIR}"
      return 1
    fi
  done
}

backup_current() {
  mkdir -p "${PRIZRAK_BACKUP_DIR}"
  cp -f "${PRIZRAK_BIN}" "${PRIZRAK_BACKUP_DIR}/prizrak-core"
}

backup_geo() {
  geo_backup_dir="${PRIZRAK_BACKUP_DIR}/geo"
  rm -rf "${geo_backup_dir}"
  mkdir -p "${geo_backup_dir}"
  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    if [ -e "${PRIZRAK_CONFIG_DIR}/${geo_asset}" ]; then
      cp -f "${PRIZRAK_CONFIG_DIR}/${geo_asset}" "${geo_backup_dir}/${geo_asset}"
    else
      : >"${geo_backup_dir}/${geo_asset}.missing"
    fi
  done
}

apply_binary() {
  mkdir -p "$(dirname "${PRIZRAK_BIN}")"
  cp -f "${STAGED_BIN}" "${PRIZRAK_BIN}"
  chmod +x "${PRIZRAK_BIN}"
}

apply_geo() {
  mkdir -p "${PRIZRAK_CONFIG_DIR}"
  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    tmp="${PRIZRAK_CONFIG_DIR}/.${geo_asset}.tmp"
    cp -f "${STAGED_GEO_DIR}/${geo_asset}" "${tmp}"
    mv -f "${tmp}" "${PRIZRAK_CONFIG_DIR}/${geo_asset}"
  done
}

restore_backup() {
  cp -f "${PRIZRAK_BACKUP_DIR}/prizrak-core" "${PRIZRAK_BIN}"
  chmod +x "${PRIZRAK_BIN}"
}

restore_geo() {
  geo_backup_dir="${PRIZRAK_BACKUP_DIR}/geo"
  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    if [ -e "${geo_backup_dir}/${geo_asset}" ]; then
      mkdir -p "${PRIZRAK_CONFIG_DIR}"
      cp -f "${geo_backup_dir}/${geo_asset}" "${PRIZRAK_CONFIG_DIR}/${geo_asset}"
    else
      rm -f "${PRIZRAK_CONFIG_DIR}/${geo_asset}"
    fi
  done
}

strip_yaml_value() {
  sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//'
}

controller_from_config() {
  config="${PRIZRAK_CONFIG_DIR}/config.yaml"
  [ -f "${config}" ] || return 1
  sed -n 's/^[[:space:]]*external-controller:[[:space:]]*//p' "${config}" | strip_yaml_value | sed -n '1p'
}

secret_from_config() {
  config="${PRIZRAK_CONFIG_DIR}/config.yaml"
  [ -f "${config}" ] || return 1
  sed -n 's/^[[:space:]]*secret:[[:space:]]*//p' "${config}" | strip_yaml_value | sed -n '1p'
}

normalize_controller_url() {
  url="$1"
  case "${url}" in
    http://*|https://*) printf '%s\n' "${url}" ;;
    :*) printf 'http://127.0.0.1%s\n' "${url}" ;;
    *) printf 'http://%s\n' "${url}" ;;
  esac
}

soft_restart() {
  url="${PRIZRAK_CONTROLLER_URL:-}"
  secret="${PRIZRAK_SECRET:-}"

  if [ -z "${url}" ]; then
    url="$(controller_from_config || true)"
  fi
  if [ -z "${secret}" ]; then
    secret="$(secret_from_config || true)"
  fi
  [ -n "${url}" ] || return 1

  url="$(normalize_controller_url "${url}")"
  if [ -n "${secret}" ]; then
    ${PRIZRAK_CURL} -fsS -X POST -H "Authorization: Bearer ${secret}" "${url%/}/restart" >/dev/null || return 1
  else
    ${PRIZRAK_CURL} -fsS -X POST "${url%/}/restart" >/dev/null || return 1
  fi
}

restart_core() {
  if soft_restart; then
    RESTART_MODE="soft"
    return 0
  fi
  RESTART_MODE="hard"
  eval "${PRIZRAK_RESTART_CMD}" || return 1
}

read_pidfile() {
  [ -f "${PRIZRAK_PID_FILE}" ] || return 1
  pid="$(sed -n '1{s/[[:space:]]*$//;p;q;}' "${PRIZRAK_PID_FILE}")"
  case "${pid}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "${pid}"
}

pid_is_alive() {
  pid="$1"
  case "${pid}" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "${pid}" 2>/dev/null
}

capture_health_pid() {
  PRIZRAK_HEALTH_OLD_PID=""
  if [ -f "${PRIZRAK_PID_FILE}" ]; then
    PRIZRAK_HEALTH_OLD_PID="$(sed -n '1{s/[[:space:]]*$//;p;q;}' "${PRIZRAK_PID_FILE}" || true)"
  fi
}

probe_controller() {
  url="${PRIZRAK_CONTROLLER_URL:-}"
  secret="${PRIZRAK_SECRET:-}"

  if [ -z "${url}" ]; then
    url="$(controller_from_config || true)"
  fi
  if [ -z "${url}" ]; then
    return 0
  fi
  if [ -z "${secret}" ]; then
    secret="$(secret_from_config || true)"
  fi

  url="$(normalize_controller_url "${url}")"
  if [ -n "${secret}" ]; then
    ${PRIZRAK_CURL} -fsS --max-time "${PRIZRAK_HEALTH_PROBE_TIMEOUT}" \
      -H "Authorization: Bearer ${secret}" \
      "${url%/}/version" >/dev/null || return 1
  else
    ${PRIZRAK_CURL} -fsS --max-time "${PRIZRAK_HEALTH_PROBE_TIMEOUT}" \
      "${url%/}/version" >/dev/null || return 1
  fi
}

default_health() {
  attempts=$((PRIZRAK_HEALTH_WAIT_SEC * 5))
  settle_ticks=$((PRIZRAK_HEALTH_SETTLE_SEC * 5))
  if [ "${attempts}" -lt 1 ]; then
    attempts=1
  fi

  stable=0
  stable_pid=""
  i=0
  while [ "${i}" -lt "${attempts}" ]; do
    pid="$(read_pidfile || true)"
    candidate=0
    if pid_is_alive "${pid}"; then
      if [ "${RESTART_MODE}" != "hard" ] || [ -z "${PRIZRAK_HEALTH_OLD_PID}" ] || [ "${pid}" != "${PRIZRAK_HEALTH_OLD_PID}" ]; then
        candidate=1
      fi
    fi

    if [ "${candidate}" -eq 1 ] && [ "${pid}" = "${stable_pid}" ]; then
      stable=$((stable + 1))
    elif [ "${candidate}" -eq 1 ]; then
      stable_pid="${pid}"
      stable=1
    else
      stable=0
      stable_pid=""
    fi

    if [ "${candidate}" -eq 1 ] && [ "${stable}" -gt "${settle_ticks}" ]; then
      if probe_controller; then
        return 0
      fi
    fi

    i=$((i + 1))
    sleep 0.2
  done
  return 1
}

run_health() {
  if [ "${PRIZRAK_HEALTH_CMD}" = "default_health" ]; then
    default_health || return 1
  else
    eval "${PRIZRAK_HEALTH_CMD}" || return 1
  fi
}

rollback_apply() {
  restore_backup
  restore_geo
  restart_core || true
  rm -rf "${PRIZRAK_STAGE_DIR}"
  exit 1
}

write_state() {
  tag="$1"
  mkdir -p "$(dirname "${PRIZRAK_STATE_FILE}")"
  tmp="${PRIZRAK_STATE_FILE}.tmp"
  printf '%s\n' "${tag}" >"${tmp}"
  mv -f "${tmp}" "${PRIZRAK_STATE_FILE}"
}

new_tag="$(latest_tag)"
old_tag="$(current_tag || true)"

if [ "${new_tag}" = "${old_tag}" ]; then
  exit 0
fi

stage_and_verify "${new_tag}"
backup_current
backup_geo
apply_binary
apply_geo
capture_health_pid

if ! restart_core || ! run_health; then
  rollback_apply
fi

write_state "${new_tag}"
rm -rf "${PRIZRAK_STAGE_DIR}"
