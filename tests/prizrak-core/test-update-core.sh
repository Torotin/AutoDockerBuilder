#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPDATE="${ROOT}/bin/prizrak-core/update-core.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -x "${UPDATE}" ] || fail "missing executable updater: ${UPDATE}"

setup_case() {
  local name="$1"
  TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/prizrak-update-${name}.XXXXXX")"
  export PRIZRAK_BIN="${TEST_ROOT}/opt/prizrak/prizrak-core"
  export PRIZRAK_STATE_FILE="${TEST_ROOT}/opt/prizrak/installed-release"
  export PRIZRAK_STAGE_DIR="${TEST_ROOT}/temp/prizrak-update"
  export PRIZRAK_BACKUP_DIR="${TEST_ROOT}/temp/prizrak-backup"
  export PRIZRAK_LOCK_FILE="${TEST_ROOT}/temp/prizrak-update.lock"
  export PRIZRAK_CONFIG_DIR="${TEST_ROOT}/root/.config/mihomo"
  export PRIZRAK_CURL="${TEST_ROOT}/fake-curl.sh"
  export PRIZRAK_HEALTH_CMD="true"
  export PRIZRAK_RESTART_CMD=":"
  unset PRIZRAK_CONTROLLER_URL PRIZRAK_SECRET
  mkdir -p "$(dirname "${PRIZRAK_BIN}")" "$(dirname "${PRIZRAK_STATE_FILE}")" "${PRIZRAK_CONFIG_DIR}"
  printf 'old' >"${PRIZRAK_BIN}"
  chmod +x "${PRIZRAK_BIN}"
  printf 'v1.0.0\n' >"${PRIZRAK_STATE_FILE}"
  for geo_asset in geoip.dat geosite.dat geoip.metadb; do
    printf 'old-%s' "${geo_asset}" >"${PRIZRAK_CONFIG_DIR}/${geo_asset}"
  done
}

write_fake_curl() {
  local fail_core="${1:-no}"
  cat >"${PRIZRAK_CURL}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

out=""
url=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -o|--output)
      out="\$2"
      shift 2
      ;;
    -*)
      shift
      ;;
    *)
      url="\$1"
      shift
      ;;
  esac
done

case "\${url}" in
  */releases/latest)
    printf '{"tag_name":"v2.0.0"}\n'
    ;;
  *prizrak-core-*.gz)
    [ "${fail_core}" = "no" ] || exit 23
    [ -n "\${out}" ] || exit 2
    printf 'new' | gzip -c >"\${out}"
    ;;
  */geoip.dat|*/geosite.dat|*/geoip.metadb)
    [ -n "\${out}" ] || exit 2
    printf 'new-%s' "\${url##*/}" >"\${out}"
    ;;
  *)
    printf 'unexpected URL: %s\n' "\${url}" >&2
    exit 3
    ;;
esac
EOF
  chmod +x "${PRIZRAK_CURL}"
}

run_update() {
  PRIZRAK_BIN="${PRIZRAK_BIN}" \
  PRIZRAK_STATE_FILE="${PRIZRAK_STATE_FILE}" \
  PRIZRAK_STAGE_DIR="${PRIZRAK_STAGE_DIR}" \
  PRIZRAK_BACKUP_DIR="${PRIZRAK_BACKUP_DIR}" \
  PRIZRAK_LOCK_FILE="${PRIZRAK_LOCK_FILE}" \
  PRIZRAK_CONFIG_DIR="${PRIZRAK_CONFIG_DIR}" \
  PRIZRAK_CURL="${PRIZRAK_CURL}" \
  PRIZRAK_HEALTH_CMD="${PRIZRAK_HEALTH_CMD}" \
  PRIZRAK_RESTART_CMD="${PRIZRAK_RESTART_CMD}" \
  "${UPDATE}"
}

assert_file_content() {
  local path="$1"
  local want="$2"
  local got
  got="$(cat "${path}")"
  [ "${got}" = "${want}" ] || fail "${path}: got '${got}', want '${want}'"
}

test_failed_download_keeps_binary() {
  setup_case failed-download
  write_fake_curl yes

  if run_update >/tmp/prizrak-update-failed-download.log 2>&1; then
    fail "expected failed core download to fail"
  fi

  assert_file_content "${PRIZRAK_BIN}" old
  [ ! -e "${PRIZRAK_BACKUP_DIR}/prizrak-core" ] || fail "backup should not be created before download succeeds"
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.dat" old-geoip.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geosite.dat" old-geosite.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.metadb" old-geoip.metadb
}

test_failed_health_restores_backup() {
  setup_case failed-health
  write_fake_curl no
  export PRIZRAK_HEALTH_CMD="false"

  if run_update >/tmp/prizrak-update-failed-health.log 2>&1; then
    fail "expected failed health to fail"
  fi

  assert_file_content "${PRIZRAK_BIN}" old
  assert_file_content "${PRIZRAK_STATE_FILE}" v1.0.0
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.dat" old-geoip.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geosite.dat" old-geosite.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.metadb" old-geoip.metadb
}

test_success_advances_state() {
  setup_case success
  write_fake_curl no

  run_update >/tmp/prizrak-update-success.log 2>&1

  assert_file_content "${PRIZRAK_BIN}" new
  assert_file_content "${PRIZRAK_STATE_FILE}" v2.0.0
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.dat" new-geoip.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geosite.dat" new-geosite.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.metadb" new-geoip.metadb
  [ ! -d "${PRIZRAK_STAGE_DIR}" ] || fail "stage dir should be cleaned after success"
}

test_failed_download_keeps_binary
test_failed_health_restores_backup
test_success_advances_state
printf 'OK test-update-core\n'
