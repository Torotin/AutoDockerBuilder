#!/usr/bin/env bash
set -Eeuo pipefail

: "${TOR_PROXY_HEALTHCHECK_URL:=https://check.torproject.org/api/ip}"
: "${TOR_PROXY_LOGIN:=}"
: "${TOR_PROXY_PASSWORD:=}"

proxy_auth=()
if [ -n "${TOR_PROXY_LOGIN}" ] && [ -n "${TOR_PROXY_PASSWORD}" ]; then
    proxy_auth=(--proxy-user "${TOR_PROXY_LOGIN}:${TOR_PROXY_PASSWORD}")
fi

curl --fail --silent --show-error --max-time 15 \
    "${proxy_auth[@]}" \
    --socks5-hostname 127.0.0.1:1080 "${TOR_PROXY_HEALTHCHECK_URL}" |
    jq -e '.IsTor == true' >/dev/null
