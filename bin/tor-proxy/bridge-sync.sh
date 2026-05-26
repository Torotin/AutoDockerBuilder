#!/usr/bin/env bash
set -Eeuo pipefail

: "${TOR_PROXY_CACHE_DIR:=/var/lib/tor-proxy/bridges}"
: "${TOR_BRIDGES_CONFIG:=/etc/tor/bridges.generated.conf}"
: "${TOR_BRIDGE_TRANSPORT:=auto}"
: "${TOR_BRIDGES_MAX_PER_TRANSPORT:=2}"
: "${TOR_IPV6_AVAILABLE:=auto}"
: "${TOR_BRIDGES_BUILTIN_DEFAULTS:=/usr/local/share/tor-proxy/pt_config.json}"
: "${TOR_BRIDGES_OBFS4_URL:=https://raw.githubusercontent.com/scriptzteam/Tor-Bridges-Collector/refs/heads/main/bridges-obfs4}"
: "${TOR_BRIDGES_OBFS4_IPV6_URL:=https://raw.githubusercontent.com/scriptzteam/Tor-Bridges-Collector/refs/heads/main/bridges-obfs4-ipv6}"
: "${TOR_BRIDGES_WEBTUNNEL_URL:=https://raw.githubusercontent.com/scriptzteam/Tor-Bridges-Collector/refs/heads/main/bridges-webtunnel}"
: "${TOR_BRIDGES_SNOWFLAKE_URL:=https://gitlab.torproject.org/tpo/applications/tor-browser-build/-/raw/main/projects/tor-expert-bundle/pt_config.json}"

log() {
    printf '[tor-proxy-bridges] %s\n' "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

case "${TOR_BRIDGE_TRANSPORT}" in
    auto|obfs4|webtunnel|snowflake) ;;
    *) die "TOR_BRIDGE_TRANSPORT must be auto, obfs4, webtunnel, or snowflake" ;;
esac

case "${TOR_BRIDGES_MAX_PER_TRANSPORT}" in
    ''|*[!0-9]*|0) die "TOR_BRIDGES_MAX_PER_TRANSPORT must be a positive integer" ;;
esac

mkdir -p "${TOR_PROXY_CACHE_DIR}" "$(dirname "${TOR_BRIDGES_CONFIG}")"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

normalize_lines() {
    local expected="$1"
    local input="$2"
    local output="$3"

    awk -v expected="${expected}" '
        {
            sub(/\r$/, "")
            if ($0 ~ /^[[:space:]]*($|#)/) next
            if ($1 == "Bridge" && $2 == expected) {
                print
            } else if ($1 == expected) {
                print "Bridge " $0
            }
        }
    ' "${input}" | awk '!seen[$0]++' > "${output}"
}

filter_network_usable_lines() {
    local input="$1"
    local output="$2"

    if [ "${allow_ipv6_bridges}" = "true" ]; then
        cp "${input}" "${output}"
        return 0
    fi

    awk '
        {
            endpoint = ($1 == "Bridge" ? $3 : $2)
            if (endpoint !~ /^\[/) print
        }
    ' "${input}" > "${output}"
}

extract_snowflake_input() {
    local input="$1"
    local output="$2"

    if jq -e '.bridges.snowflake | type == "array"' "${input}" >/dev/null 2>&1; then
        jq -r '.bridges.snowflake[]' "${input}" > "${output}"
    else
        cp "${input}" "${output}"
    fi
}

source_dataset() {
    local name="$1"
    local transport="$2"
    local url="$3"
    local output="$4"
    local raw="${work_dir}/${name}.raw"
    local extracted="${work_dir}/${name}.extracted"
    local valid="${work_dir}/${name}.valid"
    local cache="${TOR_PROXY_CACHE_DIR}/${name}.conf"

    if curl -fsSL --connect-timeout 10 --max-time 45 --retry 2 --retry-delay 1 \
        "${url}" -o "${raw}"; then
        if [ "${transport}" = "snowflake" ]; then
            extract_snowflake_input "${raw}" "${extracted}"
        else
            cp "${raw}" "${extracted}"
        fi
        normalize_lines "${transport}" "${extracted}" "${valid}"
        if [ -s "${valid}" ]; then
            cp "${valid}" "${cache}"
            log "${name}: refreshed $(wc -l < "${valid}" | tr -d ' ') validated ${transport} bridges"
            filter_network_usable_lines "${valid}" "${output}"
            if [ -s "${output}" ]; then
                return 0
            fi
            log "WARN: ${name} source has no network-usable ${transport} bridges"
        else
            log "WARN: ${name} source returned no valid ${transport} bridges"
        fi
    else
        log "WARN: failed to download ${name} source"
    fi

    if [ -s "${cache}" ]; then
        filter_network_usable_lines "${cache}" "${output}"
        if [ -s "${output}" ]; then
            log "${name}: using cached validated ${transport} bridges"
            return 0
        fi
        log "WARN: ${name} cache has no network-usable ${transport} bridges"
    fi
    return 1
}

builtin_dataset() {
    local transport="$1"
    local output="$2"
    local raw="${work_dir}/builtin-${transport}.raw"

    [ -s "${TOR_BRIDGES_BUILTIN_DEFAULTS}" ] || return 1
    jq -r --arg transport "${transport}" '.bridges[$transport][]?' \
        "${TOR_BRIDGES_BUILTIN_DEFAULTS}" > "${raw}"
    normalize_lines "${transport}" "${raw}" "${work_dir}/builtin-${transport}.valid"
    filter_network_usable_lines "${work_dir}/builtin-${transport}.valid" "${output}"
    [ -s "${output}" ] || return 1
    log "${transport}: using bundled official Tor Browser defaults"
}

ipv6_is_available() {
    case "${TOR_IPV6_AVAILABLE}" in
        true|1|yes) return 0 ;;
        false|0|no) return 1 ;;
        auto)
            curl -6 -fsS --connect-timeout 3 --max-time 5 \
                https://check.torproject.org/api/ip >/dev/null 2>&1
            ;;
        *) die "TOR_IPV6_AVAILABLE must be auto, true, or false" ;;
    esac
}

append_sample() {
    local transport="$1"
    local pool="$2"

    [ -s "${pool}" ] || return 0
    shuf -n "${TOR_BRIDGES_MAX_PER_TRANSPORT}" "${pool}" >> "${TOR_BRIDGES_CONFIG}"
    log "${transport}: selected at most ${TOR_BRIDGES_MAX_PER_TRANSPORT} bridges for this start"
}

allow_ipv6_bridges=false
if ipv6_is_available; then
    allow_ipv6_bridges=true
    log "IPv6 bridge endpoints enabled because outbound IPv6 is available"
else
    log "IPv6 bridge endpoints filtered because outbound IPv6 is unavailable"
fi

obfs4_pool="${work_dir}/obfs4.pool"
webtunnel_pool="${work_dir}/webtunnel.pool"
snowflake_pool="${work_dir}/snowflake.pool"
: > "${obfs4_pool}"
: > "${webtunnel_pool}"
: > "${snowflake_pool}"

if [ "${TOR_BRIDGE_TRANSPORT}" = "auto" ] || [ "${TOR_BRIDGE_TRANSPORT}" = "obfs4" ]; then
    if ! source_dataset obfs4 obfs4 "${TOR_BRIDGES_OBFS4_URL}" "${obfs4_pool}"; then
        builtin_dataset obfs4 "${obfs4_pool}" || true
    fi

    if [ "${allow_ipv6_bridges}" = "true" ]; then
        ipv6_pool="${work_dir}/obfs4-ipv6.pool"
        if source_dataset obfs4-ipv6 obfs4 "${TOR_BRIDGES_OBFS4_IPV6_URL}" "${ipv6_pool}"; then
            cat "${ipv6_pool}" >> "${obfs4_pool}"
            awk '!seen[$0]++' "${obfs4_pool}" > "${work_dir}/obfs4.deduped"
            mv "${work_dir}/obfs4.deduped" "${obfs4_pool}"
        fi
    else
        log "obfs4-ipv6: skipped because outbound IPv6 is unavailable"
    fi
fi

if [ "${TOR_BRIDGE_TRANSPORT}" = "auto" ] || [ "${TOR_BRIDGE_TRANSPORT}" = "webtunnel" ]; then
    source_dataset webtunnel webtunnel "${TOR_BRIDGES_WEBTUNNEL_URL}" "${webtunnel_pool}" || true
fi

if [ "${TOR_BRIDGE_TRANSPORT}" = "auto" ] || [ "${TOR_BRIDGE_TRANSPORT}" = "snowflake" ]; then
    if ! source_dataset snowflake snowflake "${TOR_BRIDGES_SNOWFLAKE_URL}" "${snowflake_pool}"; then
        builtin_dataset snowflake "${snowflake_pool}" || true
    fi
fi

: > "${TOR_BRIDGES_CONFIG}"
case "${TOR_BRIDGE_TRANSPORT}" in
    auto)
        append_sample webtunnel "${webtunnel_pool}"
        append_sample obfs4 "${obfs4_pool}"
        append_sample snowflake "${snowflake_pool}"
        ;;
    obfs4) append_sample obfs4 "${obfs4_pool}" ;;
    webtunnel) append_sample webtunnel "${webtunnel_pool}" ;;
    snowflake) append_sample snowflake "${snowflake_pool}" ;;
esac

[ -s "${TOR_BRIDGES_CONFIG}" ] || die "no valid bridges available for ${TOR_BRIDGE_TRANSPORT} mode"
log "generated bridge configuration with $(wc -l < "${TOR_BRIDGES_CONFIG}" | tr -d ' ') selected bridges"
