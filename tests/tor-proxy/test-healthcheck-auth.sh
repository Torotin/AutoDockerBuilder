#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/tor-proxy/healthcheck.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "${tmp}/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${CALL_LOG}"
printf '%s\n' '{"IsTor":true}'
EOF
chmod +x "${tmp}/curl"

CALL_LOG="${tmp}/curl.args" \
PATH="${tmp}:${PATH}" \
TOR_PROXY_LOGIN=alice \
TOR_PROXY_PASSWORD=secret \
"${SCRIPT}"

grep -Fx -- '--proxy-user' "${tmp}/curl.args" >/dev/null
grep -Fx -- 'alice:secret' "${tmp}/curl.args" >/dev/null
printf 'PASS: healthcheck proxy authentication\n'
