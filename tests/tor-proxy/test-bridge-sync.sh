#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/tor-proxy/bridge-sync.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    file="$1"
    value="$2"
    grep -Fqx "$value" "$file" || fail "missing expected line: ${value}"
}

assert_not_contains() {
    file="$1"
    value="$2"
    ! grep -Fqx "$value" "$file" || fail "unexpected line: ${value}"
}

assert_line_count() {
    file="$1"
    expected="$2"
    actual="$(wc -l < "$file" | tr -d ' ')"
    [ "$actual" = "$expected" ] || fail "expected ${expected} lines in ${file}, got ${actual}"
}

make_fixtures() {
    fixture_dir="$1"

    cat > "${fixture_dir}/obfs4.txt" <<'EOF'
obfs4 198.51.100.10:443 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA cert=abc iat-mode=0
Bridge obfs4 198.51.100.11:443 BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB cert=def iat-mode=0
webtunnel 198.51.100.30:443 CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC url=https://wrong.invalid
EOF

    cat > "${fixture_dir}/obfs4-ipv6.txt" <<'EOF'
obfs4 [2001:db8::10]:443 DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD cert=ipv6 iat-mode=0
EOF

    cat > "${fixture_dir}/webtunnel.txt" <<'EOF'
webtunnel 192.0.2.1:443 EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE url=https://bridge.example/a
webtunnel 192.0.2.1:443 EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE url=https://bridge.example/a
EOF

    cat > "${fixture_dir}/snowflake.json" <<'EOF'
{"bridges":{"snowflake":["snowflake 192.0.2.3:80 FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF url=https://snowflake.example fronts=front.example"]}}
EOF

    cat > "${fixture_dir}/defaults.json" <<'EOF'
{"bridges":{"obfs4":["obfs4 203.0.113.10:443 1111111111111111111111111111111111111111 cert=builtin iat-mode=0"],"snowflake":["snowflake 192.0.2.4:80 2222222222222222222222222222222222222222 url=https://builtin.example fronts=front.example"]}}
EOF
}

run_sync() {
    cache_dir="$1"
    output="$2"
    defaults="$3"
    mode="$4"
    ipv6="$5"
    max="$6"
    obfs4_url="$7"
    ipv6_url="$8"
    webtunnel_url="$9"
    snowflake_url="${10}"

    TOR_PROXY_CACHE_DIR="$cache_dir" \
    TOR_BRIDGES_CONFIG="$output" \
    TOR_BRIDGE_TRANSPORT="$mode" \
    TOR_BRIDGES_MAX_PER_TRANSPORT="$max" \
    TOR_IPV6_AVAILABLE="$ipv6" \
    TOR_BRIDGES_BUILTIN_DEFAULTS="$defaults" \
    TOR_BRIDGES_OBFS4_URL="$obfs4_url" \
    TOR_BRIDGES_OBFS4_IPV6_URL="$ipv6_url" \
    TOR_BRIDGES_WEBTUNNEL_URL="$webtunnel_url" \
    TOR_BRIDGES_SNOWFLAKE_URL="$snowflake_url" \
    "$SCRIPT"
}

test_fetch_filter_deduplicate_and_exclude_ipv6() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    make_fixtures "$tmp"

    run_sync "$tmp/cache" "$tmp/out.conf" "$tmp/defaults.json" auto false 32 \
        "file://${tmp}/obfs4.txt" "file://${tmp}/obfs4-ipv6.txt" \
        "file://${tmp}/webtunnel.txt" "file://${tmp}/snowflake.json"

    assert_contains "$tmp/out.conf" "Bridge webtunnel 192.0.2.1:443 EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE url=https://bridge.example/a"
    assert_contains "$tmp/out.conf" "Bridge obfs4 198.51.100.10:443 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA cert=abc iat-mode=0"
    assert_contains "$tmp/out.conf" "Bridge snowflake 192.0.2.3:80 FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF url=https://snowflake.example fronts=front.example"
    assert_not_contains "$tmp/out.conf" "Bridge obfs4 [2001:db8::10]:443 DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD cert=ipv6 iat-mode=0"
    assert_line_count "$tmp/out.conf" 4
}

test_cache_then_bundled_fallback() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    make_fixtures "$tmp"

    run_sync "$tmp/cache" "$tmp/first.conf" "$tmp/defaults.json" obfs4 false 32 \
        "file://${tmp}/obfs4.txt" "file://${tmp}/missing-ipv6" \
        "file://${tmp}/missing-web" "file://${tmp}/missing-snow"
    rm -f "$tmp/obfs4.txt"
    run_sync "$tmp/cache" "$tmp/cached.conf" "$tmp/defaults.json" obfs4 false 32 \
        "file://${tmp}/obfs4.txt" "file://${tmp}/missing-ipv6" \
        "file://${tmp}/missing-web" "file://${tmp}/missing-snow"
    assert_contains "$tmp/cached.conf" "Bridge obfs4 198.51.100.10:443 AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA cert=abc iat-mode=0"

    run_sync "$tmp/new-cache" "$tmp/builtin.conf" "$tmp/defaults.json" obfs4 false 32 \
        "file://${tmp}/missing-obfs4" "file://${tmp}/missing-ipv6" \
        "file://${tmp}/missing-web" "file://${tmp}/missing-snow"
    assert_contains "$tmp/builtin.conf" "Bridge obfs4 203.0.113.10:443 1111111111111111111111111111111111111111 cert=builtin iat-mode=0"
}

test_explicit_webtunnel_requires_feed_or_cache() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    make_fixtures "$tmp"

    if run_sync "$tmp/cache" "$tmp/out.conf" "$tmp/defaults.json" webtunnel false 32 \
        "file://${tmp}/missing-obfs4" "file://${tmp}/missing-ipv6" \
        "file://${tmp}/missing-web" "file://${tmp}/missing-snow"; then
        fail "webtunnel-only mode unexpectedly succeeded without feed or cache"
    fi
}

test_limit_selected_bridge_count() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    make_fixtures "$tmp"

    run_sync "$tmp/cache" "$tmp/out.conf" "$tmp/defaults.json" obfs4 false 1 \
        "file://${tmp}/obfs4.txt" "file://${tmp}/missing-ipv6" \
        "file://${tmp}/missing-web" "file://${tmp}/missing-snow"
    assert_line_count "$tmp/out.conf" 1
}

test_fetch_filter_deduplicate_and_exclude_ipv6
test_cache_then_bundled_fallback
test_explicit_webtunnel_requires_feed_or_cache
test_limit_selected_bridge_count
printf 'PASS: bridge-sync behavior\n'
