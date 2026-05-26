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
    grep -Fqx -- "$pattern" "$file" || fail "missing '${pattern}' in ${file}"
}

test_generates_local_tor_and_dns_forwarders() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    TOR_RUNTIME_CONFIG_ONLY=true \
    TOR_UPDATE_ON_START=false \
    TOR_BRIDGES_ENABLED=false \
    TOR_IPV6_AVAILABLE=false \
    TOR_CONFIG_DIR="${tmp}/tor" \
    TOR_DATA_DIR="${tmp}/data" \
    TOR_PROXY_STATE_DIR="${tmp}/proxy" \
    TOR_RESOLV_CONF="${tmp}/resolv.conf" \
    DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
    bash "$SCRIPT"

    assert_grep "SocksPort 127.0.0.1:9050 IPv6Traffic" "${tmp}/tor/torrc"
    assert_grep "DNSPort 127.0.0.1:5353" "${tmp}/tor/torrc"
    assert_grep "MaxClientCircuitsPending 4" "${tmp}/tor/torrc"
    assert_grep "ClientUseIPv6 0" "${tmp}/tor/torrc"
    assert_grep "ClientTransportPlugin obfs4,webtunnel,snowflake exec /usr/local/bin/lyrebird" "${tmp}/tor/torrc"
    ! grep -q '^UseBridges ' "${tmp}/tor/torrc" || fail "bridges unexpectedly enabled"
    assert_grep "server=127.0.0.1#5353" "${tmp}/dnsmasq.conf"
    assert_grep "port=53" "${tmp}/dnsmasq.conf"
    assert_grep "interface=eth0" "${tmp}/dnsmasq.conf"
    assert_grep "except-interface=lo" "${tmp}/dnsmasq.conf"
    ! grep -q '^listen-address=127.0.0.1' "${tmp}/dnsmasq.conf" ||
        fail "public DNS configuration overlaps bootstrap listener"
}

test_generates_ipv6_client_mode_when_available() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN

    TOR_RUNTIME_CONFIG_ONLY=true \
    TOR_UPDATE_ON_START=false \
    TOR_BRIDGES_ENABLED=false \
    TOR_IPV6_AVAILABLE=true \
    TOR_BOOTSTRAP_DNS_ENABLED=false \
    TOR_CONFIG_DIR="${tmp}/tor" \
    TOR_DATA_DIR="${tmp}/data" \
    TOR_PROXY_STATE_DIR="${tmp}/proxy" \
    DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
    bash "$SCRIPT"

    assert_grep "ClientUseIPv6 1" "${tmp}/tor/torrc"
}

test_generates_encrypted_bootstrap_dns_arguments() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    printf 'nameserver 127.0.0.11\n' > "${tmp}/resolv.conf"

    TOR_RUNTIME_CONFIG_ONLY=true \
    TOR_UPDATE_ON_START=false \
    TOR_BRIDGES_ENABLED=false \
    TOR_IPV6_AVAILABLE=false \
    TOR_BOOTSTRAP_DNS_UPSTREAMS='https://resolver.example/dns-query tls://resolver.example quic://resolver.example' \
    TOR_BOOTSTRAP_DNS_BOOTSTRAPS='192.0.2.53:53' \
    TOR_CONFIG_DIR="${tmp}/tor" \
    TOR_DATA_DIR="${tmp}/data" \
    TOR_PROXY_STATE_DIR="${tmp}/proxy" \
    TOR_RESOLV_CONF="${tmp}/resolv.conf" \
    DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
    bash "$SCRIPT"

    assert_grep "--upstream=https://resolver.example/dns-query" "${tmp}/proxy/dnsproxy.args"
    assert_grep "--upstream=tls://resolver.example" "${tmp}/proxy/dnsproxy.args"
    assert_grep "--upstream=quic://resolver.example" "${tmp}/proxy/dnsproxy.args"
    assert_grep "--upstream-mode=parallel" "${tmp}/proxy/dnsproxy.args"
    assert_grep "--bootstrap=192.0.2.53:53" "${tmp}/proxy/dnsproxy.args"
    assert_grep "--fallback=127.0.0.11:53" "${tmp}/proxy/dnsproxy.args"
}

test_can_disable_plain_bootstrap_dns_fallback() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    printf 'nameserver 127.0.0.11\n' > "${tmp}/resolv.conf"

    TOR_RUNTIME_CONFIG_ONLY=true \
    TOR_UPDATE_ON_START=false \
    TOR_BRIDGES_ENABLED=false \
    TOR_IPV6_AVAILABLE=false \
    TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK=false \
    TOR_CONFIG_DIR="${tmp}/tor" \
    TOR_DATA_DIR="${tmp}/data" \
    TOR_PROXY_STATE_DIR="${tmp}/proxy" \
    TOR_RESOLV_CONF="${tmp}/resolv.conf" \
    DNSMASQ_CONFIG="${tmp}/dnsmasq.conf" \
    bash "$SCRIPT"

    ! grep -q -- '^--fallback=' "${tmp}/proxy/dnsproxy.args" ||
        fail "plaintext bootstrap DNS fallback unexpectedly enabled"
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
        bash "$SCRIPT" 2>"${tmp}/stderr"; then
        fail "entrypoint accepted partial credentials"
    fi
    grep -q 'TOR_PROXY_LOGIN and TOR_PROXY_PASSWORD must be set together' "${tmp}/stderr" ||
        fail "partial credential failure was not diagnosed"
}

test_generates_local_tor_and_dns_forwarders
test_generates_ipv6_client_mode_when_available
test_generates_encrypted_bootstrap_dns_arguments
test_can_disable_plain_bootstrap_dns_fallback
test_partial_proxy_credentials_fail_validation
printf 'PASS: entrypoint configuration behavior\n'
