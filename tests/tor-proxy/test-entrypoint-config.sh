#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/tor-proxy/entrypoint.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_grep() {
    pattern="$1"
    file="$2"
    grep -Fqx "$pattern" "$file" || fail "missing '${pattern}' in ${file}"
}

test_generates_local_tor_and_dns_forwarders() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    TOR_RUNTIME_CONFIG_ONLY=true \
    TOR_UPDATE_ON_START=false \
    TOR_BRIDGES_ENABLED=false \
    TOR_CONFIG_DIR="${tmp}/tor" \
    TOR_DATA_DIR="${tmp}/data" \
    TOR_PROXY_STATE_DIR="${tmp}/proxy" \
    DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
    "$SCRIPT"

    assert_grep "SocksPort 127.0.0.1:9050" "${tmp}/tor/torrc"
    assert_grep "DNSPort 127.0.0.1:5353" "${tmp}/tor/torrc"
    assert_grep "ClientTransportPlugin obfs4,webtunnel,snowflake exec /usr/local/bin/lyrebird" "${tmp}/tor/torrc"
    ! grep -q '^UseBridges ' "${tmp}/tor/torrc" || fail "bridges unexpectedly enabled"
    assert_grep "server=127.0.0.1#5353" "${tmp}/dnsmasq.conf"
    assert_grep "port=53" "${tmp}/dnsmasq.conf"
}

test_partial_proxy_credentials_fail_validation() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    if TOR_RUNTIME_CONFIG_ONLY=true \
        TOR_UPDATE_ON_START=false \
        TOR_BRIDGES_ENABLED=false \
        TOR_PROXY_LOGIN=user \
        TOR_PROXY_PASSWORD='' \
        TOR_CONFIG_DIR="${tmp}/tor" \
        TOR_DATA_DIR="${tmp}/data" \
        TOR_PROXY_STATE_DIR="${tmp}/proxy" \
        DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
        "$SCRIPT" 2>"${tmp}/stderr"; then
        fail "entrypoint accepted partial credentials"
    fi
    grep -q 'TOR_PROXY_LOGIN and TOR_PROXY_PASSWORD must be set together' "${tmp}/stderr" ||
        fail "partial credential failure was not diagnosed"
}

test_generates_local_tor_and_dns_forwarders
test_partial_proxy_credentials_fail_validation
printf 'PASS: entrypoint configuration behavior\n'
