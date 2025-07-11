#!/bin/sh
set -e

CONFIG="/etc/warp/config.json"
mkdir -p "$(dirname "$CONFIG")"

# === Значения по умолчанию ===
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
: "${TEST_URL:=}"
: "${IPV4:=true}"
: "${IPV6:=false}"

echo "[INFO] Генерация конфигурации warp-plus..."

json="{"

add_field() {
  key="$1"
  val="$2"
  type="$3" # "string" или "raw"

  [ -n "$val" ] || return 0
  [ "$val" = "null" ] && return 0

  [ "$json" != "{" ] && json="$json,"

  if [ "$type" = "string" ]; then
    json="$json\"$key\":\"$val\""
  else
    json="$json\"$key\":$val"
  fi
}

# === Обработка полей ===
add_field "verbose"        "$VERBOSE"        raw
add_field "bind"           "$BIND"           string
add_field "endpoint"       "$ENDPOINT"       string
add_field "key"            "$KEY"            string
add_field "dns"            "$DNS"            string
add_field "gool"           "$GOOL"           raw
add_field "cfon"           "$CFON"           raw
add_field "country"        "$COUNTRY"        string
add_field "scan"           "$SCAN"           raw
add_field "rtt"            "$RTT"            string
add_field "cache-dir"      "$CACHE_DIR"      string
add_field "fwmark"         "$FWMARK"         string
add_field "wgconf"         "$WGCONF"         string
add_field "reserved"       "$RESERVED"       string
add_field "test-url"       "$TEST_URL"       string

# === Взаимоисключающая логика 4 vs 6 ===
if [ "$IPV4" = "true" ] || [ "$IPV4" = "1" ]; then
  add_field "4" true raw
elif [ "$IPV6" = "true" ] || [ "$IPV6" = "1" ]; then
  add_field "6" true raw
fi

json="$json}"

# === Проверка JSON ===
if ! echo "$json" | jq . > "$CONFIG" 2>/dev/null; then
  echo "[ERROR] Сгенерирован некорректный JSON:"
  echo "$json"
  exit 1
fi

# === Предупреждение, если пустой JSON ===
if [ "$json" = "{}" ]; then
  echo "[WARN] Конфигурация пуста. Ни одна переменная не была задана."
  echo "[HINT] Установите переменные окружения, например KEY или BIND"
fi

echo "[INFO] Конфигурация успешно создана:"
cat "$CONFIG"

echo "[INFO] Запуск warp-plus..."
exec /usr/bin/warp-plus -c "$CONFIG"
