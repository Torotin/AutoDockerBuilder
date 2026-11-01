#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/bin/prizrak-core/asset-name.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

got="$(prizrak_asset_name linux amd64 v3 v1.19.33-r8)"
[ "${got}" = "prizrak-core-linux-amd64-v3-v1.19.33-r8.gz" ] || fail "amd64 v3: ${got}"

got="$(prizrak_asset_name linux amd64 v1 v1.19.33-r8)"
[ "${got}" = "prizrak-core-linux-amd64-v1-v1.19.33-r8.gz" ] || fail "amd64 v1: ${got}"

got="$(prizrak_asset_name linux arm64 v3 v1.19.33-r8)"
[ "${got}" = "prizrak-core-linux-arm64-v1.19.33-r8.gz" ] || fail "arm64: ${got}"

if prizrak_asset_name linux amd64 v9 v1.0.0 >/dev/null 2>&1; then
  fail "expected invalid variant to fail"
fi

printf 'OK test-asset-name\n'
