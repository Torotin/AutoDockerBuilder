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
  export PRIZRAK_HEALTH_WAIT_SEC="15"
  export PRIZRAK_HEALTH_SETTLE_SEC="1"
  export PRIZRAK_PID_FILE="${TEST_ROOT}/temp/prizrak-core.pid"
  export PRIZRAK_RESTART_CMD=":"
  unset PRIZRAK_CONTROLLER_URL PRIZRAK_SECRET
  mkdir -p "$(dirname "${PRIZRAK_BIN}")" "$(dirname "${PRIZRAK_STATE_FILE}")" "${PRIZRAK_CONFIG_DIR}" "$(dirname "${PRIZRAK_PID_FILE}")"
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
  *)
    geo_base="\${PRIZRAK_GEO_BASE_URL:-https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest}"
    case "\${url}" in
      "\${geo_base}/geoip.dat"|"\${geo_base}/geosite.dat"|"\${geo_base}/geoip.metadb")
        [ -n "\${out}" ] || exit 2
        printf 'new-%s' "\${url##*/}" >"\${out}"
        exit 0
        ;;
    esac
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
  PRIZRAK_HEALTH_CMD="${PRIZRAK_HEALTH_CMD-}" \
  PRIZRAK_HEALTH_WAIT_SEC="${PRIZRAK_HEALTH_WAIT_SEC}" \
  PRIZRAK_HEALTH_SETTLE_SEC="${PRIZRAK_HEALTH_SETTLE_SEC}" \
  PRIZRAK_PID_FILE="${PRIZRAK_PID_FILE}" \
  PRIZRAK_RESTART_CMD="${PRIZRAK_RESTART_CMD}" \
  "${UPDATE}"
}

stop_health_pid() {
  if [ -f "${PRIZRAK_PID_FILE}.all" ]; then
    while read -r pid; do
      kill "${pid}" 2>/dev/null || true
    done <"${PRIZRAK_PID_FILE}.all"
  fi
  if [ -f "${PRIZRAK_PID_FILE}" ]; then
    kill "$(cat "${PRIZRAK_PID_FILE}")" 2>/dev/null || true
  fi
}

assert_unchanged_install() {
  assert_file_content "${PRIZRAK_BIN}" old
  assert_file_content "${PRIZRAK_STATE_FILE}" v1.0.0
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.dat" old-geoip.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geosite.dat" old-geosite.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.metadb" old-geoip.metadb
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

  assert_unchanged_install
}

test_restart_failure_restores_install() {
  setup_case restart-failure
  write_fake_curl no
  export PRIZRAK_RESTART_CMD="kill -TERM 999999"

  if run_update >/tmp/prizrak-update-restart-failure.log 2>&1; then
    fail "expected restart failure to fail"
  fi

  assert_unchanged_install
}

test_default_health_requires_live_process() {
  setup_case default-health-dead
  write_fake_curl no
  unset PRIZRAK_HEALTH_CMD
  export PRIZRAK_HEALTH_WAIT_SEC=1
  # shellcheck disable=SC2016
  export PRIZRAK_RESTART_CMD='printf "999999\n" >"${PRIZRAK_PID_FILE}"'

  if run_update >/tmp/prizrak-update-default-health-dead.log 2>&1; then
    fail "expected default health to fail when the pid is not alive"
  fi

  assert_unchanged_install
}

test_default_health_accepts_live_process() {
  setup_case default-health-live
  write_fake_curl no
  unset PRIZRAK_HEALTH_CMD
  export PRIZRAK_HEALTH_WAIT_SEC=3
  export PRIZRAK_HEALTH_SETTLE_SEC=0
  # shellcheck disable=SC2016
  export PRIZRAK_RESTART_CMD='sleep 30 & printf "%s\n" "$!" >>"${PRIZRAK_PID_FILE}.all"; printf "%s\n" "$!" >"${PRIZRAK_PID_FILE}"'

  run_update >/tmp/prizrak-update-default-health-live.log 2>&1
  stop_health_pid

  assert_file_content "${PRIZRAK_BIN}" new
  assert_file_content "${PRIZRAK_STATE_FILE}" v2.0.0
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.dat" new-geoip.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geosite.dat" new-geosite.dat
  assert_file_content "${PRIZRAK_CONFIG_DIR}/geoip.metadb" new-geoip.metadb
}

test_hard_restart_rejects_unchanged_live_pid() {
  setup_case hard-restart-same-pid
  write_fake_curl no
  unset PRIZRAK_HEALTH_CMD
  export PRIZRAK_HEALTH_WAIT_SEC=1
  export PRIZRAK_HEALTH_SETTLE_SEC=0
  sleep 30 &
  old_pid="$!"
  printf '%s\n' "${old_pid}" >"${PRIZRAK_PID_FILE}"
  export PRIZRAK_RESTART_CMD=":"

  set +e
  run_update >/tmp/prizrak-update-hard-same-pid.log 2>&1
  update_status="$?"
  set -e
  kill "${old_pid}" 2>/dev/null || true

  [ "${update_status}" -ne 0 ] || fail "expected hard restart to reject the pre-restart pid"
  assert_unchanged_install
}

test_controller_probe_failure_restores() {
  setup_case probe-failure
  write_fake_curl no
  unset PRIZRAK_HEALTH_CMD
  export PRIZRAK_HEALTH_WAIT_SEC=1
  export PRIZRAK_HEALTH_SETTLE_SEC=0
  export PRIZRAK_CONTROLLER_URL="http://127.0.0.1:9090"
  # shellcheck disable=SC2016
  export PRIZRAK_RESTART_CMD='sleep 30 & printf "%s\n" "$!" >>"${PRIZRAK_PID_FILE}.all"; printf "%s\n" "$!" >"${PRIZRAK_PID_FILE}"'

  if run_update >/tmp/prizrak-update-probe-failure.log 2>&1; then
    stop_health_pid
    fail "expected controller probe failure to fail"
  fi
  stop_health_pid

  assert_unchanged_install
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
test_restart_failure_restores_install
test_default_health_requires_live_process
test_default_health_accepts_live_process
test_hard_restart_rejects_unchanged_live_pid
test_controller_probe_failure_restores
test_success_advances_state
printf 'OK test-update-core\n'
