#!/bin/sh
set -eu

. "$(dirname "$0")/asset-name.sh"

PRIZRAK_BIN="${PRIZRAK_BIN:-/opt/prizrak/prizrak-core}"
PRIZRAK_STATE_FILE="${PRIZRAK_STATE_FILE:-/opt/prizrak/installed-release}"
PRIZRAK_STAGE_DIR="${PRIZRAK_STAGE_DIR:-/temp/prizrak-update}"
PRIZRAK_BACKUP_DIR="${PRIZRAK_BACKUP_DIR:-/temp/prizrak-backup}"
PRIZRAK_LOCK_FILE="${PRIZRAK_LOCK_FILE:-/temp/prizrak-update.lock}"
PRIZRAK_CONFIG_DIR="${PRIZRAK_CONFIG_DIR:-/root/.config/mihomo}"
PRIZRAK_REPO="${PRIZRAK_REPO:-legiz-ru/Prizrak-Core}"
PRIZRAK_CORE_VARIANT="${PRIZRAK_CORE_VARIANT:-v3}"
PRIZRAK_CURL="${PRIZRAK_CURL:-curl}"
PRIZRAK_HEALTH_CMD="${PRIZRAK_HEALTH_CMD:-true}"
PRIZRAK_RESTART_CMD="${PRIZRAK_RESTART_CMD:-:}"

STAGED_BIN="${PRIZRAK_STAGE_DIR}/prizrak-core"

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
  geo_dir="${PRIZRAK_STAGE_DIR}/geo"

  rm -rf "${PRIZRAK_STAGE_DIR}"
  mkdir -p "${geo_dir}"

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
    if ! download_file "${release_url}/${geo_asset}" "${geo_dir}/${geo_asset}"; then
      rm -rf "${PRIZRAK_STAGE_DIR}"
      return 1
    fi
  done
}

backup_current() {
  mkdir -p "${PRIZRAK_BACKUP_DIR}"
  cp -f "${PRIZRAK_BIN}" "${PRIZRAK_BACKUP_DIR}/prizrak-core"
}

apply_binary() {
  mkdir -p "$(dirname "${PRIZRAK_BIN}")"
  cp -f "${STAGED_BIN}" "${PRIZRAK_BIN}"
  chmod +x "${PRIZRAK_BIN}"
}

restore_backup() {
  cp -f "${PRIZRAK_BACKUP_DIR}/prizrak-core" "${PRIZRAK_BIN}"
  chmod +x "${PRIZRAK_BIN}"
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
    ${PRIZRAK_CURL} -fsS -X POST -H "Authorization: Bearer ${secret}" "${url%/}/restart" >/dev/null
  else
    ${PRIZRAK_CURL} -fsS -X POST "${url%/}/restart" >/dev/null
  fi
}

restart_core() {
  if soft_restart; then
    return 0
  fi
  eval "${PRIZRAK_RESTART_CMD}"
}

run_health() {
  eval "${PRIZRAK_HEALTH_CMD}"
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
apply_binary
restart_core

if ! run_health; then
  restore_backup
  restart_core
  rm -rf "${PRIZRAK_STAGE_DIR}"
  exit 1
fi

write_state "${new_tag}"
rm -rf "${PRIZRAK_STAGE_DIR}"
