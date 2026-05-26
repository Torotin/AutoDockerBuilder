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
: "${TOR_IPV6_AVAILABLE:=auto}"
: "${TOR_MAX_CLIENT_CIRCUITS_PENDING:=4}"
: "${TOR_BOOTSTRAP_DNS_ENABLED:=true}"
: "${TOR_BOOTSTRAP_DNS_UPSTREAMS:=https://dns.adguard-dns.com/dns-query tls://dns.adguard-dns.com quic://dns.adguard-dns.com}"
: "${TOR_BOOTSTRAP_DNS_BOOTSTRAPS:=94.140.14.14:53 94.140.15.15:53}"
: "${TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK:=true}"
: "${TOR_BOOTSTRAP_DNS_FALLBACKS:=}"
: "${TOR_BOOTSTRAP_DNS_ARGS_FILE:=${TOR_PROXY_STATE_DIR}/dnsproxy.args}"
: "${TOR_RESOLV_CONF:=/etc/resolv.conf}"
: "${TOR_PROXY_LOGIN:=}"
: "${TOR_PROXY_PASSWORD:=}"
: "${TOR_RUNTIME_CONFIG_ONLY:=false}"

tor_pid=""
dnsmasq_pid=""
gost_pid=""
dnsproxy_pid=""

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
    case "${TOR_MAX_CLIENT_CIRCUITS_PENDING}" in
        ''|*[!0-9]*|0) die "TOR_MAX_CLIENT_CIRCUITS_PENDING must be a positive integer" ;;
    esac
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
        "${TOR_PROXY_STATE_DIR}" "$(dirname "${DNSMASQ_CONFIG}")"
    if [ "$(id -u)" -eq 0 ] && getent passwd debian-tor >/dev/null 2>&1; then
        chown -R debian-tor:debian-tor "${TOR_DATA_DIR}"
        chmod 0700 "${TOR_DATA_DIR}"
    fi
}

resolver_with_port() {
    case "$1" in
        \[*\]:*) printf '%s\n' "$1" ;;
        \[*\]) printf '%s:53\n' "$1" ;;
        *:*:*) printf '[%s]:53\n' "$1" ;;
        *:*) printf '%s\n' "$1" ;;
        *) printf '%s:53\n' "$1" ;;
    esac
}

generate_bootstrap_dns_args() {
    local upstream bootstrap fallback nameserver
    local -a upstreams bootstraps fallbacks

    : > "${TOR_BOOTSTRAP_DNS_ARGS_FILE}"
    is_true "${TOR_BOOTSTRAP_DNS_ENABLED}" || return 0

    read -r -a upstreams <<< "${TOR_BOOTSTRAP_DNS_UPSTREAMS}"
    read -r -a bootstraps <<< "${TOR_BOOTSTRAP_DNS_BOOTSTRAPS}"
    {
        printf '%s\n' '--listen=127.0.0.1' '--port=53' '--cache' '--pending-requests-enabled' \
            '--timeout=5s' '--max-go-routines=64' '--upstream-mode=parallel'
        for upstream in "${upstreams[@]}"; do
            printf '%s\n' "--upstream=${upstream}"
        done
        for bootstrap in "${bootstraps[@]}"; do
            printf '%s\n' "--bootstrap=${bootstrap}"
        done
    } >> "${TOR_BOOTSTRAP_DNS_ARGS_FILE}"

    is_true "${TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK}" || return 0
    if [ -n "${TOR_BOOTSTRAP_DNS_FALLBACKS}" ]; then
        read -r -a fallbacks <<< "${TOR_BOOTSTRAP_DNS_FALLBACKS}"
    elif [ -f "${TOR_RESOLV_CONF}" ]; then
        mapfile -t fallbacks < <(awk '$1 == "nameserver" {print $2}' "${TOR_RESOLV_CONF}")
    fi
    for fallback in "${fallbacks[@]}"; do
        [ -z "${fallback}" ] || {
            nameserver="$(resolver_with_port "${fallback}")"
            printf '%s\n' "--fallback=${nameserver}" >> "${TOR_BOOTSTRAP_DNS_ARGS_FILE}"
        }
    done
}

start_bootstrap_dns() {
    local -a args

    is_true "${TOR_BOOTSTRAP_DNS_ENABLED}" || {
        log "encrypted bootstrap DNS disabled"
        return 0
    }
    mapfile -t args < "${TOR_BOOTSTRAP_DNS_ARGS_FILE}"
    dnsproxy "${args[@]}" >/dev/null 2>&1 &
    dnsproxy_pid="$!"
    sleep 0.2
    kill -0 "${dnsproxy_pid}" 2>/dev/null || die "encrypted bootstrap DNS failed to start"
    cp "${TOR_RESOLV_CONF}" "${TOR_PROXY_STATE_DIR}/resolv.conf.original"
    printf 'nameserver 127.0.0.1\noptions ndots:0\n' > "${TOR_RESOLV_CONF}"
    log "encrypted bootstrap DNS enabled with plaintext fallback policy=${TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK}"
}

resolve_ipv6_mode() {
    case "${TOR_IPV6_AVAILABLE}" in
        true|1|yes) TOR_IPV6_AVAILABLE=true ;;
        false|0|no) TOR_IPV6_AVAILABLE=false ;;
        auto)
            if curl -6 -fsS --connect-timeout 3 --max-time 5 \
                https://check.torproject.org/api/ip >/dev/null 2>&1; then
                TOR_IPV6_AVAILABLE=true
            else
                TOR_IPV6_AVAILABLE=false
            fi
            ;;
        *) die "TOR_IPV6_AVAILABLE must be auto, true, or false" ;;
    esac
    export TOR_IPV6_AVAILABLE
    log "outbound IPv6 for bridge connections: ${TOR_IPV6_AVAILABLE}"
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
SocksPort 127.0.0.1:9050 IPv6Traffic
DNSPort 127.0.0.1:5353
AutomapHostsOnResolve 1
VirtualAddrNetworkIPv4 10.192.0.0/10
MaxClientCircuitsPending ${TOR_MAX_CLIENT_CIRCUITS_PENDING}
ClientUseIPv6 $(is_true "${TOR_IPV6_AVAILABLE}" && printf 1 || printf 0)
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
interface=eth0
except-interface=lo
bind-dynamic
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
    for pid in "${gost_pid}" "${dnsmasq_pid}" "${tor_pid}" "${dnsproxy_pid}"; do
        if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    for pid in "${gost_pid}" "${dnsmasq_pid}" "${tor_pid}" "${dnsproxy_pid}"; do
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
    local -a pids
    auth="$(encoded_auth)"

    log "starting Tor, DNS-over-Tor proxy, SOCKS5 proxy, and HTTP proxy; client circuit cap=${TOR_MAX_CLIENT_CIRCUITS_PENDING}"
    tor -f "${TOR_CONFIG_DIR}/torrc" &
    tor_pid="$!"
    dnsmasq --keep-in-foreground --conf-file="${DNSMASQ_CONFIG}" &
    dnsmasq_pid="$!"
    gost -L "socks5://${auth}:1080" -L "http://${auth}:8080" \
        -F "socks5://127.0.0.1:9050" >/dev/null 2>&1 &
    gost_pid="$!"

    pids=("${tor_pid}" "${dnsmasq_pid}" "${gost_pid}")
    [ -z "${dnsproxy_pid}" ] || pids+=("${dnsproxy_pid}")
    set +e
    wait -n "${pids[@]}"
    exit_code="$?"
    set -e
    terminate_processes "${exit_code}"
}

validate_environment
prepare_directories
generate_bootstrap_dns_args

if ! is_true "${TOR_RUNTIME_CONFIG_ONLY}"; then
    trap 'terminate_processes 143' TERM INT
    start_bootstrap_dns
fi

update_tor_package
resolve_ipv6_mode
prepare_bridges
generate_tor_config
generate_dnsmasq_config

if is_true "${TOR_RUNTIME_CONFIG_ONLY}"; then
    log "configuration generated; runtime launch skipped"
    exit 0
fi

log "runtime versions: $(tor --version | head -n 1); $(lyrebird --version 2>&1 | head -n 1); $(gost -V 2>&1 | head -n 1); $(dnsproxy --version 2>&1 | head -n 1)"
start_services
