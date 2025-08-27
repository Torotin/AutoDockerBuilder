#!/bin/ash
# Надёжные опции для ash
set -eu
# Включим pipefail, если поддерживается текущей ash
(set -o pipefail) 2>/dev/null && set -o pipefail || true

PIDS=""
CONFIG="/etc/warp/config.json"
TEMPLATE="/etc/warp/config.json.template"
mkdir -p "$(dirname "$CONFIG")"

# === Defaults ===
: "${VERBOSE:=false}"
: "${BIND:=0.0.0.0:1080}"
: "${ENDPOINT:=}"
: "${KEY:=}"
: "${DNS:=9.9.9.9}"
: "${GOOL:=false}"
: "${CFON:=false}"
: "${COUNTRY:=}"
: "${SCAN:=true}"
: "${RTT:=1s}"
: "${CACHE_DIR:=/etc/warp/cache/}"
: "${TUN_EXPERIMENTAL:=false}"
: "${FWMARK:=0x1375}"
: "${WGCONF:=}"
: "${RESERVED:=}"
: "${TEST_URL:=}"
: "${IPV4:=false}"
: "${IPV6:=false}"
: "${EXCLUDE_COUNTRY:=RU IR CN}"
: "${LOGLEVEL:=INFO}"

log() {
    local level=$1; shift
    level=$(printf '%s' "$level" | tr -d '[:space:]')
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local current active color reset='\033[0m'
    case "$level" in ERROR) current=1 ;; WARN*) current=2 ;; INFO) current=3 ;; DEBUG) current=4 ;; *) current=3 ;; esac
    case "$LOGLEVEL" in ERROR) active=1 ;; WARN*) active=2 ;; INFO) active=3 ;; DEBUG) active=4 ;; *) active=3 ;; esac
    [ "$current" -gt "$active" ] && return
    case "$level" in
      INFO) color='\033[1;34m' ;; WARN*) color='\033[1;33m' ;;
      ERROR) color='\033[1;31m' ;; DEBUG) color='\033[1;36m' ;; *) color='\033[0m' ;;
    esac
    printf "%s %b%s%b - %s\n" "$timestamp" "$color" "$level" "$reset" "$*" >&2
}

add_pid() { PIDS="${PIDS:+$PIDS }$1"; }

kill_all() {
  log WARN "Stopping background processes..."
  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
  wait || true
}

reload_ignore() { log INFO "Received SIGUSR1 — ignoring."; }

setup_signal_handlers() {
  trap reload_ignore USR1
  trap 'kill_all; log INFO "All processes stopped."; exit 0' TERM INT QUIT
}

rand_bit() { awk 'BEGIN{srand(); print int(rand()*2)}'; }

set_random_bool_if_equal() {
    # $1, $2 — имена булевых переменных (true/false/1/0/yes/no)
    local var1_name=$1 var2_name=$2 var1 var2
    eval "var1=\${$var1_name:-false}"; eval "var2=\${$var2_name:-false}"
    log INFO "Checking variables: $var1_name=$var1, $var2_name=$var2"
    if [ "$var1" = "$var2" ]; then
        log INFO "Both variables equal ($var1). Randomizing one to false."
        if [ "$(rand_bit)" -eq 0 ]; then
            eval "$var1_name=false"
            log INFO "Set $var1_name=false"
        else
            eval "$var2_name=false"
            log INFO "Set $var2_name=false"
        fi
    fi
    eval "export $var1_name"; eval "export $var2_name"
}

force_ipv4_if_no_ipv6() {
    log INFO "Checking external IPv6 connectivity..."
    if command -v curl >/dev/null 2>&1; then
        if curl -6 -m 5 -s --output /dev/null https://ifconfig.co; then
            log INFO "External IPv6 connectivity is available."
        else
            log WARN "IPv6 is not available. Forcing IPv4."
            IPV4=true; IPV6=false
            export IPV4 IPV6
            log INFO "Set IPV4=true, IPV6=false"
        fi
    else
        log ERROR "curl not found. Cannot check IPv6 connectivity."
    fi
}

proxy_addr_from_bind() {
  # Возвращаем 127.0.0.1:PORT для любой формы BIND
  local bind="${BIND}" port=""
  case "$bind" in *:*) port="${bind##*:}" ;; esac
  [ -n "$port" ] || port=1080
  echo "127.0.0.1:${port}"
}
healthcheck_loop() {
  local interval="${HEALTHCHECK_INTERVAL:-300}"
  local timeout="${HEALTHCHECK_TIMEOUT:-30}"
  local max_fails="${HEALTHCHECK_MAX_FAILURES:-3}"
  local attempts="${HEALTHCHECK_ATTEMPTS:-2}"           # сколько раз пробовать в одном цикле
  local initial_delay="${HEALTHCHECK_INITIAL_DELAY:-60}"
  local proxy="${HEALTHCHECK_PROXY:-$(proxy_addr_from_bind)}"

  # Можно задать несколько адресов проб — берём из HEALTHCHECK_URLS или fallback к HEALTHCHECK_URL, затем к Cloudflare trace
  local urls="${HEALTHCHECK_URLS:-${HEALTHCHECK_URL:-https://ifconfig.me} https://www.cloudflare.com/cdn-cgi/trace}"

  log INFO "Starting healthcheck via SOCKS5: $urls"
  log INFO "Initial delay: ${initial_delay}s, interval: ${interval}s, attempts: ${attempts}, failure threshold: $max_fails"

  sleep "$initial_delay"

  while :; do
    local ok=0 output="" url

    for url in $urls; do
      # Пара попыток на каждый URL
      local i=1
      while [ $i -le $attempts ]; do
        if output=$(curl --socks5-hostname "$proxy" -sS -f \
                          --connect-timeout "$timeout" --max-time "$timeout" \
                          "$url"); then
          ok=1
          break
        fi
        log WARN "Healthcheck: attempt $i/$attempts failed for $url via $proxy"
        i=$((i+1))
        sleep 1
      done
      [ $ok -eq 1 ] && break
    done

    if [ $ok -ne 1 ]; then
      log ERROR "Healthcheck: all attempts failed for URLs: $urls via $proxy — stopping container."
      kill 1
    fi

    # Опциональная проверка поля "fails" в JSON (если используете тестовый эндпоинт, который его отдаёт)
    local fails
    fails=$(printf '%s\n' "$output" | grep -o '"fails":[0-9]\+' | cut -d: -f2 | tr -d '\r')
    if [ -n "$fails" ]; then
      for count in $fails; do
        if [ "$count" -ge "$max_fails" ]; then
          log ERROR "Healthcheck: upstream fails=$count ≥ $max_fails — restarting."
          kill 1
        fi
      done
      log DEBUG "Healthcheck: Healthy (fails: $fails)"
    else
      log DEBUG "Healthcheck: Healthy (content OK, no 'fails' field)."
    fi

    # Небольшой джиттер (±10%) чтобы не совпадать с чужими крон-окнами
    # Если не нужен — можно просто sleep "$interval"
    local jitter_ms
    jitter_ms=$(awk -v i="$interval" 'BEGIN{srand(); print int((rand()*0.2 - 0.1)*i*1000)}')
    local base_ms=$((interval*1000))
    local sleep_ms=$((base_ms + jitter_ms))
    [ "$sleep_ms" -lt 0 ] && sleep_ms=0
    # sleep миллисекундно (busybox sleep в секундах; используем awk для дробного)
    awk -v ms="$sleep_ms" 'BEGIN{ system("sleep " ms/1000) }'
  done
}

# Безопасное добавление полей в JSON: строки экранируем через jq, raw — как есть.
json_add_string() { # $1 key, $2 value
  local key="$1" val="$2"
  [ -n "$val" ] || return 0
  [ "$val" = "null" ] && return 0
  [ "$json" != "{" ] && json="$json,"
  json="$json\"$key\":$(printf '%s' "$val" | jq -Rs .)"
}
json_add_raw() { # $1 key, $2 value (true/false/числа/готовые литералы)
  local key="$1" val="$2"
  [ -n "$val" ] || return 0
  [ "$val" = "null" ] && return 0
  [ "$json" != "{" ] && json="$json,"
  json="$json\"$key\":$val"
}

prepare_config() {
  # Сначала разрешаем конфликтующие флаги, затем форсим IPv4 при отсутствии v6
  set_random_bool_if_equal GOOL CFON
  set_random_bool_if_equal IPV4 IPV6
  force_ipv4_if_no_ipv6

  # === Country selection ===
  local COUNTRY_LIST="AT BE BG BR CA CH CZ DE DK EE ES FI FR GB HR HU IE IN IT JP LV NL NO PL PT RO RS SE SG SK UA US"
  local EXCLUDE_LIST FILTERED_COUNTRY_LIST
  EXCLUDE_LIST=$(echo "$EXCLUDE_COUNTRY" | tr ',;' ' ' | tr '[:lower:]' '[:upper:]' | xargs)

  FILTERED_COUNTRY_LIST=$(for c in $COUNTRY_LIST; do
    echo "$EXCLUDE_LIST" | grep -qw "$c" || echo "$c"
  done)

  if [ -z "$COUNTRY" ]; then
    # Используем awk вместо shuf, чтобы не зависеть от coreutils (на всякий случай)
    COUNTRY=$(printf '%s\n' $FILTERED_COUNTRY_LIST | awk 'BEGIN{srand()} {a[NR]=$0} END{if(NR)print a[int(rand()*NR)+1]}')
    log INFO "COUNTRY not set. Randomly selected: $COUNTRY"
  else
    local found=0 c
    for c in $FILTERED_COUNTRY_LIST; do [ "$c" = "$COUNTRY" ] && found=1 && break; done
    if [ $found -eq 0 ]; then
      local prev="$COUNTRY"
      COUNTRY=$(printf '%s\n' $FILTERED_COUNTRY_LIST | awk 'BEGIN{srand()} {a[NR]=$0} END{if(NR)print a[int(rand()*NR)+1]}')
      log WARN "COUNTRY '$prev' is excluded. Randomly selected: $COUNTRY"
    fi
  fi

  # === JSON ===
  json="{"
  json_add_raw    "verbose"      "$([ "$VERBOSE" = "true" ] && echo true || echo false)"
  json_add_string "bind"         "$BIND"
  json_add_string "endpoint"     "$ENDPOINT"
  json_add_string "key"          "$KEY"
  json_add_string "dns"          "$DNS"
  json_add_raw    "gool"         "$([ "$GOOL" = "true" ] && echo true || echo false)"
  json_add_raw    "cfon"         "$([ "$CFON" = "true" ] && echo true || echo false)"
  json_add_string "country"      "$COUNTRY"
  json_add_raw    "scan"         "$([ "$SCAN" = "true" ] && echo true || echo false)"
  json_add_string "rtt"          "$RTT"
  json_add_string "cache-dir"    "$CACHE_DIR"
  json_add_string "fwmark"       "$FWMARK"
  json_add_string "wgconf"       "$WGCONF"
  json_add_string "reserved"     "$RESERVED"
  json_add_string "test-url"     "$TEST_URL"
  [ "$IPV4" = "true" ] && json_add_raw "4" true
  [ "$IPV6" = "true" ] && json_add_raw "6" true
  [ "$TUN_EXPERIMENTAL" = "true" ] && json_add_raw "tun-experimental" true
  json="$json}"

  if ! echo "$json" | jq . > "$CONFIG" 2>/dev/null; then
    log ERROR "Invalid JSON generated:"
    echo "$json" >&2
    exit 1
  fi

  log INFO "Config successfully created:"
  cat "$CONFIG"
}

main() {
  # Respect pre-existing config unless forced to regenerate
  if [ -f "$CONFIG" ] && [ "${REGENERATE_CONFIG:-false}" != "true" ]; then
    log INFO "Found existing config at $CONFIG; skipping regeneration."
  else
    if [ -f "$TEMPLATE" ] && [ "${USE_TEMPLATE:-false}" = "true" ]; then
      log INFO "Using config template at $TEMPLATE"
      cp -f "$TEMPLATE" "$CONFIG"
    else
      prepare_config
    fi
  fi

  setup_signal_handlers

  # Run healthcheck loop only when not explicitly disabled
  if [ "${DISABLE_HEALTHCHECK:-false}" != "true" ]; then
    log INFO "Launching healthcheck background loop..."
    healthcheck_loop & add_pid $!
  else
    log INFO "Healthcheck disabled by env"
  fi

  log INFO "Starting warp-plus..."
  exec /usr/bin/warp-plus -c "$CONFIG"
}

main
