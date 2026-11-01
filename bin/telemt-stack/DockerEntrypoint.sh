#!/usr/bin/env bash
set -Eeuo pipefail

: "${TELEMT_PANEL_ENABLED:=true}"
: "${TELEMT_GEOIP_IMAGE_DIR:=/usr/share/telemt-panel/geoip}"
: "${TELEMT_GEOIP_DATA_DIR:=/var/lib/telemt-panel/geoip}"
: "${TELEMT_GEOIP_SEED:=true}"

telemt_pid=""
telemt_panel_pid=""

log() {
    printf '[telemt-stack] %s\n' "$*" >&2
}

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Copy baked MMDB into data_dir-friendly paths without overwriting existing files.
# Keeps ensure-geoip / URL workflows intact when the consumer already provisioned DBs.
seed_geoip() {
    if ! is_true "${TELEMT_GEOIP_SEED}"; then
        log "GeoIP seed disabled"
        return 0
    fi
    if [ ! -d "${TELEMT_GEOIP_IMAGE_DIR}" ]; then
        log "GeoIP image dir missing: ${TELEMT_GEOIP_IMAGE_DIR}"
        return 0
    fi
    mkdir -p "${TELEMT_GEOIP_DATA_DIR}"
    for name in GeoLite2-City.mmdb GeoLite2-ASN.mmdb GeoLite2-Country.mmdb SOURCE.txt; do
        src="${TELEMT_GEOIP_IMAGE_DIR}/${name}"
        dst="${TELEMT_GEOIP_DATA_DIR}/${name}"
        if [ -f "${src}" ] && [ ! -e "${dst}" ]; then
            cp -f "${src}" "${dst}"
            chmod 0644 "${dst}" || true
            log "seeded GeoIP ${dst}"
        fi
    done
}

terminate_processes() {
    exit_code="${1:-143}"
    trap - TERM INT

    if [ -n "${telemt_pid}" ] && kill -0 "${telemt_pid}" 2>/dev/null; then
        kill -TERM "${telemt_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_panel_pid}" ] && kill -0 "${telemt_panel_pid}" 2>/dev/null; then
        kill -TERM "${telemt_panel_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_pid}" ]; then
        wait "${telemt_pid}" 2>/dev/null || true
    fi

    if [ -n "${telemt_panel_pid}" ]; then
        wait "${telemt_panel_pid}" 2>/dev/null || true
    fi

    exit "${exit_code}"
}

trap 'terminate_processes 143' TERM INT

seed_geoip

log "starting telemt"
telemt /etc/telemt/config.toml &
telemt_pid="$!"

set +e
if is_true "${TELEMT_PANEL_ENABLED}"; then
    log "starting bundled telemt-panel"
    telemt-panel --config /etc/telemt-panel/config.toml &
    telemt_panel_pid="$!"
    wait -n "${telemt_pid}" "${telemt_panel_pid}"
else
    log "bundled telemt-panel disabled; waiting for telemt only"
    wait "${telemt_pid}"
fi
exit_code="$?"
set -e

terminate_processes "${exit_code}"
