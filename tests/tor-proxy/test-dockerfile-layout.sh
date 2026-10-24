#!/usr/bin/env bash
# Re-run without CR if this file was materialised with CRLF (Samba/autocrlf).
# Avoid `{`/`}` here: CRLF checkouts break brace groups before re-exec.
# $_TOR_PROXY_LAYOUT_TEST_SCRIPT and $@ must expand in the child bash -c, not here.
# shellcheck disable=SC2016
[ -n "${_TOR_PROXY_LAYOUT_TEST_NORCR:-}" ] || exec env _TOR_PROXY_LAYOUT_TEST_NORCR=1 _TOR_PROXY_LAYOUT_TEST_SCRIPT="$0" bash -c 'tr -d "\r" <"$_TOR_PROXY_LAYOUT_TEST_SCRIPT" | bash -s -- "$@"' bash "$@"
set -euo pipefail

ROOT="$(cd "$(dirname "${_TOR_PROXY_LAYOUT_TEST_SCRIPT:-${BASH_SOURCE[0]}}")/../.." && pwd)"
DOCKERFILE="${ROOT}/bin/tor-proxy/Dockerfile"
WORKFLOW="${ROOT}/.github/workflows/TorProxy-Docker-selfhosted.yml"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

test -f "${DOCKERFILE}" || fail "missing ${DOCKERFILE}"
test -f "${WORKFLOW}" || fail "missing ${WORKFLOW}"

# Strip CR so anchored greps work under core.autocrlf on Windows checkouts.
dockerfile="$(tr -d '\r' < "${DOCKERFILE}")"
workflow="$(tr -d '\r' < "${WORKFLOW}")"

grep -qE '^FROM .+ AS dnsproxy-download$' <<<"${dockerfile}" ||
    fail "Dockerfile missing stage AS dnsproxy-download"
if grep -qE '^FROM .+ AS dnsproxy-builder$' <<<"${dockerfile}"; then
    fail "Dockerfile still has dnsproxy-builder stage"
fi

grep -qE '^ARG PT_CONFIG_REF=' <<<"${dockerfile}" ||
    fail "Dockerfile missing ARG PT_CONFIG_REF default"
grep -qF 'raw/${PT_CONFIG_REF}/projects/tor-expert-bundle/pt_config.json' <<<"${dockerfile}" ||
    fail 'Dockerfile does not fetch pt_config via ${PT_CONFIG_REF}'
if grep -q 'raw/main/projects/tor-expert-bundle/pt_config.json' <<<"${dockerfile}"; then
    fail "Dockerfile still fetches pt_config from raw/main"
fi

grep -q 'PT_CONFIG_REF=' <<<"${workflow}" ||
    fail "workflow does not pass PT_CONFIG_REF build-arg"
grep -q 'pt_config_ref' <<<"${workflow}" ||
    fail "workflow missing pt_config_ref output/resolution"

grep -q 'autoremove' <<<"${dockerfile}" ||
    fail "Dockerfile missing apt autoremove purge after Tor install"
grep -q 'gnupg' <<<"${dockerfile}" ||
    fail "Dockerfile should still mention gnupg for install-then-purge"

printf 'OK: tor-proxy Dockerfile/workflow layout\n'
