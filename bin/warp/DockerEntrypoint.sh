#!/bin/sh
set -e

TEMPLATE="/app/config.json.template"
CONFIG="/etc/warp/config.json"

# Установить значения по умолчанию, если переменные не заданы
: "${VERBOSE:=false}"
: "${BIND:=127.0.0.1:1080}"
: "${ENDPOINT:=}"
: "${KEY:=}"
: "${DNS:=1.1.1.1}"
: "${GOOL:=false}"
: "${CFON:=false}"
: "${COUNTRY:=AT}"
: "${SCAN:=true}"
: "${RTT:=1s}"
: "${CACHE_DIR:=/etc/warp/cache/}"
: "${TUN_EXPERIMENTAL:=false}"
: "${FWMARK:=0x1375}"
: "${WGCONF:=}"
: "${RESERVED:=}"
: "${IPV4:=true}"
: "${IPV6:=false}"

# Обязательные переменные
if [ -z "$KEY" ]; then
  echo "[ERROR] KEY не задан. Установите переменную окружения KEY." >&2
  exit 1
fi

export VERBOSE BIND ENDPOINT KEY DNS GOOL CFON COUNTRY SCAN RTT CACHE_DIR \
       TUN_EXPERIMENTAL FWMARK WGCONF RESERVED IPV4 IPV6

# Генерация конфига
if [ ! -f "$CONFIG" ]; then
    echo "[INFO] Генерация конфигурации..."
    envsubst < "$TEMPLATE" > "$CONFIG"
    if ! jq empty "$CONFIG" >/dev/null 2>&1; then
        echo "[ERROR] Сгенерирован некорректный JSON:"
        cat "$CONFIG"
        exit 1
    fi
fi

echo "[INFO] Запуск warp-plus..."
exec /usr/bin/warp-plus -c "$CONFIG"