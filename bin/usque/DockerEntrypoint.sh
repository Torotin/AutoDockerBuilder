#!/bin/sh
set -eu

log() {
    printf '%s\n' "[usque-entrypoint] $*"
}

has_flag() {
    short_flag="$1"
    long_flag="$2"
    shift 2

    for arg in "$@"; do
        case "$arg" in
            "$short_flag"|"$long_flag"|"$long_flag"=*)
                return 0
                ;;
        esac
    done

    return 1
}

config_path="${USQUE_CONFIG:-config.json}"
device_name="${USQUE_DEVICE_NAME:-usque-docker}"
config_dir="$(dirname "$config_path")"

if [ "$config_dir" != "." ]; then
    mkdir -p "$config_dir"
fi

if [ "$#" -eq 0 ]; then
    set -- socks
fi

case "$1" in
    -*)
        exec /bin/usque "$@"
        ;;
    /bin/usque|usque)
        shift
        exec /bin/usque "$@"
        ;;
    help|version|completion)
        exec /bin/usque "$@"
        ;;
    register|enroll)
        exec /bin/usque --config "$config_path" "$@"
        ;;
esac

if has_flag "-h" "--help" "$@"; then
    exec /bin/usque "$@"
fi

mode="$1"

case "$mode" in
    socks|http-proxy|nativetun|portfw)
        ;;
    *)
        exec /bin/usque --config "$config_path" "$@"
        ;;
esac

if [ -d "$config_path" ]; then
    log "Config path '$config_path' is a directory."
    log "For file bind mounts, create the host file first: mkdir -p ./usque && touch ./usque/config.json"
    exit 1
fi

if [ ! -s "$config_path" ]; then
    log "Config '$config_path' not found; registering a new WARP device."

    if [ -n "${USQUE_JWT:-}" ]; then
        /bin/usque --config "$config_path" register --accept-tos --name "$device_name" --jwt "$USQUE_JWT"
    else
        /bin/usque --config "$config_path" register --accept-tos --name "$device_name"
    fi
fi

set -- "$@"

case "$mode" in
    socks|http-proxy)
        if ! has_flag "-b" "--bind" "$@"; then
            set -- "$@" --bind "${USQUE_BIND:-0.0.0.0}"
        fi

        if ! has_flag "-p" "--port" "$@"; then
            if [ "$mode" = "http-proxy" ]; then
                set -- "$@" --port "${USQUE_PORT_INTERNAL:-8000}"
            else
                set -- "$@" --port "${USQUE_PORT_INTERNAL:-1080}"
            fi
        fi
        ;;
esac

case "$mode" in
    socks|http-proxy|nativetun|portfw)
        if [ -n "${USQUE_JWT:-}" ] && ! has_flag "-s" "--sni-address" "$@"; then
            set -- "$@" --sni-address "${USQUE_SNI_ADDRESS:-zt-masque.cloudflareclient.com}"
        fi
        ;;
esac

if [ -n "${USQUE_EXTRA_ARGS:-}" ]; then
    # Intentionally split USQUE_EXTRA_ARGS like shell CLI text, e.g. "-d 1.1.1.1 --http2".
    # shellcheck disable=SC2086
    set -- "$@" $USQUE_EXTRA_ARGS
fi

log "Starting usque: $*"
exec /bin/usque --config "$config_path" "$@"
