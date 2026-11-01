#!/bin/sh
# Shared asset naming for Prizrak-Core release downloads.
# Safe to source from ash or bash.

prizrak_asset_name() {
  os="$1"
  arch="$2"
  variant="$3"
  tag="$4"

  case "${variant}" in
    v1|v2|v3) ;;
    *)
      echo "unsupported PRIZRAK_CORE_VARIANT: ${variant}" >&2
      return 1
      ;;
  esac

  case "${arch}" in
    amd64|x86_64)
      echo "prizrak-core-${os}-amd64-${variant}-${tag}.gz"
      ;;
    arm64|aarch64)
      echo "prizrak-core-${os}-arm64-${tag}.gz"
      ;;
    *)
      echo "unsupported arch: ${arch}" >&2
      return 1
      ;;
  esac
}
