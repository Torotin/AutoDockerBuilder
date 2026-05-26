#!/usr/bin/env bash
set -Eeuo pipefail

: "${TOR_CONFIG_DIR:=/etc/tor}"
: "${TOR_DATA_DIR:=/var/lib/tor}"
: "${TOR_PROXY_STATE_DIR:=/var/lib/tor-proxy}"
: "${TOR_PROXY_CACHE_DIR:=${TOR_PROXY_STATE_DIR}/bridges}"
: "${TOR_BRIDGES_CONFIG:=${TOR_CONFIG_DIR}/bridges.generated.conf}"
: "${DNSMASQ_CONFIG:=/etc/dnsmasq.d/tor-proxy.conf}"
: "${TOR_BRIDGES_ENABLED:=true}"
: "${TOR_UPDATE_ON_START:=true}"
: "${TOR_PROXY_LOGIN:=}"
: "${TOR_PROXY_PASSWORD:=}"
: "${TOR_RUNTIME_CONFIG_ONLY:=false}"

tor_pid=""
dnsmasq_pid=""
gost_pid=""

log() {
    printf '[tor-proxy] %s\n' "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

is_true() {
    case "${1,,}" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

validate_environment() {
    if { [ -n "${TOR_PROXY_LOGIN}" ] && [ -z "${TOR_PROXY_PASSWORD}" ]; } ||
        { [ -z "${TOR_PROXY_LOGIN}" ] && [ -n "${TOR_PROXY_PASSWORD}" ]; }; then
        die "TOR_PROXY_LOGIN and TOR_PROXY_PASSWORD must be set together"
    fi
}

update_tor_package() {
    is_true "${TOR_UPDATE_ON_START}" || return 0
    log "checking for a stable Tor package update"
    if apt-get update >/dev/null &&
        DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade tor >/dev/null; then
        log "Tor package update check completed"
    else
        log "WARN: Tor package update failed; continuing with bundled stable version"
    fi
}

prepare_directories() {
    mkdir -p "${TOR_CONFIG_DIR}" "${TOR_DATA_DIR}" "${TOR_PROXY_CACHE_DIR}" \
        "$(dirname "${DNSMASQ_CONFIG}")"
    if [ "$(id -u)" -eq 0 ] && getent passwd debian-tor >/dev/null 2>&1; then
        chown -R debian-tor:debian-tor "${TOR_DATA_DIR}"
        chmod 0700 "${TOR_DATA_DIR}"
    fi
}

prepare_bridges() {
    if is_true "${TOR_BRIDGES_ENABLED}"; then
        TOR_PROXY_CACHE_DIR="${TOR_PROXY_CACHE_DIR}" \
        TOR_BRIDGES_CONFIG="${TOR_BRIDGES_CONFIG}" \
            /usr/local/bin/tor-proxy-bridge-sync
    else
        : > "${TOR_BRIDGES_CONFIG}"
        log "bridge mode disabled"
    fi
}

generate_tor_config() {
    cat > "${TOR_CONFIG_DIR}/torrc" <<EOF
DataDirectory ${TOR_DATA_DIR}
User debian-tor
SocksPort 127.0.0.1:9050
DNSPort 127.0.0.1:5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
Log notice stdout
ClientTransportPlugin obfs4,webtunnel,snowflake exec /usr/local/bin/lyrebird
EOF

    if is_true "${TOR_BRIDGES_ENABLED}"; then
        cat >> "${TOR_CONFIG_DIR}/torrc" <<EOF
UseBridges 1
%include ${TOR_BRIDGES_CONFIG}
EOF
    fi
}

generate_dnsmasq_config() {
    cat > "${DNSMASQ_CONFIG}" <<EOF
port=53
listen-address=0.0.0.0
listen-address=::
bind-interfaces
no-resolv
no-poll
server=127.0.0.1#5353
cache-size=1000
domain-needed
bogus-priv
user=dnsmasq
EOF
}

terminate_processes() {
    local exit_code="${1:-143}"
    trap - TERM INT
    for pid in "${gost_pid}" "${dnsmasq_pid}" "${tor_pid}"; do
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    for pid in "${gost_pid}" "${dnsmasq_pid}" "${tor_pid}"; do
        [ -z "${pid}" ] || wait "${pid}" 2>/dev/null || true
    done
    exit "${exit_code}"
}

encoded_auth() {
    if [ -z "${TOR_PROXY_LOGIN}" ]; then
        printf ''
    else
        local login password
        login="$(jq -nr --arg value "${TOR_PROXY_LOGIN}" '$value | @uri')"
        password="$(jq -nr --arg value "${TOR_PROXY_PASSWORD}" '$value | @uri')"
        printf '%s:%s@' "${login}" "${password}"
    fi
}

start_services() {
    local auth
    auth="$(encoded_auth)"

    trap 'terminate_processes 143' TERM INT
    log "starting Tor, DNS proxy, SOCKS5 proxy, and HTTP proxy"
    tor -f "${TOR_CONFIG_DIR}/torrc" &
    tor_pid="$!"
    dnsmasq --keep-in-foreground --conf-file="${DNSMASQ_CONFIG}" &
    dnsmasq_pid="$!"
    gost -L "socks5://${auth}:1080" -L "http://${auth}:8080" \
        -F "socks5://127.0.0.1:9050" >/dev/null 2>&1 &
    gost_pid="$!"

    set +e
    wait -n "${tor_pid}" "${dnsmasq_pid}" "${gost_pid}"
    exit_code="$?"
    set -e
    terminate_processes "${exit_code}"
}

validate_environment
prepare_directories
update_tor_package
prepare_bridges
generate_tor_config
generate_dnsmasq_config

if is_true "${TOR_RUNTIME_CONFIG_ONLY}"; then
    log "configuration generated; runtime launch skipped"
    exit 0
fi

log "runtime versions: $(tor --version | head -n 1); $(lyrebird --version 2>&1 | head -n 1); $(gost -V 2>&1 | head -n 1)"
start_services
