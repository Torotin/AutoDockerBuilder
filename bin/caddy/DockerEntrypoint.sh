#!/usr/bin/env sh
set -euo pipefail

# ----------------------------------------
# DockerEntrypoint.sh для Caddy
# POSIX‐совместимый, Alpine Linux
# Live‐reload, синхронизация PEM и генерация сниппета
# ----------------------------------------

# --- Параметры окружения (с значениями по умолчанию) ---
CERT_DIR=${CERT_DIR:-/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory}  # Корень ACME-сертификатов
CONFIG_COOLDOWN=${CONFIG_COOLDOWN:-10}          # Пауза между перезагрузками (сек)
USE_JSON=${USE_JSON:-false}                     # Использовать JSON-конфиг вместо Caddyfile
SKIP_FUNCTIONAL=${SKIP_FUNCTIONAL:-false}       # true — только запускаем Caddy, без лупов и watcher
LOGLEVEL=${LOGLEVEL:-INFO}                      # Уровень логирования (DEBUG|INFO|WARN|ERROR)

# snippet-параметры
TMPFILE=${TMPFILE:-/tmp/defender_cidrs.txt}                                             # Временный файл CIDR
SNIPPET=${SNIPPET:-/etc/caddy/defender_bad_ranges.caddy}                                # Итоговый сниппет
SNIPPET_URLS=${SNIPPET_URLS:-"\
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_webclient.netset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/stopforumspam.ipset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/bds_atif.ipset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/stopforumspam_toxic.netset \
https://www.spamhaus.org/drop/drop.txt"}  # Список URL для обновления CIDR

# --- Глобальные переменные (дальнейшая инициализация) ---
PIDS=""                                       # Список PID фоновых задач
CONFIG_PATH=                                  # Путь к конфигу (устанавливается в load_config)
ADAPTER=                                      # Адаптер caddy (json|caddyfile)
WATCH_NAME=                                   # Для логов

# --- Функция логирования ---
log() {
    level=$1; shift
    level=$(printf '%s' "$level" | tr -d '[:space:]')
    [ -z "$level" ] && level=INFO
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    case "$level" in
        ERROR) current=1 ;; WARN*) current=2 ;; INFO) current=3 ;; DEBUG) current=4 ;; *) current=3 ;; 
    esac
    case "$LOGLEVEL" in
        ERROR) active=1 ;; WARN*) active=2 ;; INFO) active=3 ;; DEBUG) active=4 ;; *) active=3 ;; 
    esac
    [ "$current" -gt "$active" ] && return
    case "$level" in
        INFO)   color='\033[1;34m' ;; WARN*)  color='\033[1;33m' ;; ERROR) color='\033[1;31m' ;; DEBUG) color='\033[1;36m' ;; *) color='\033[0m' ;; 
    esac
    reset='\033[0m'
    printf '%s %b%s%b - %s\n' \
        "$timestamp" "$color" "$level" "$reset" "$*" >&2
}

# --- Загрузка конфигурации из переменных окружения ---
load_config() {
  if [ "$USE_JSON" = "true" ]; then
    CONFIG_PATH=/etc/caddy/config.json
    ADAPTER=json
    WATCH_NAME="JSON configs"
  else
    CONFIG_PATH=/etc/caddy/Caddyfile
    ADAPTER=caddyfile
    WATCH_NAME="Caddyfile"
  fi
  log INFO "Config loaded: adapter=$ADAPTER, cooldown=${CONFIG_COOLDOWN}s, watch=/etc/caddy"
}

# --- Управление PID фоновых процессов ---
add_pid() {
  PIDS="$PIDS $1"
}
kill_all() {
  log WARN "Остановка фоновых процессов..."
  for pid in $PIDS; do
    kill "$pid" 2>/dev/null || true
  done
  wait
}

# --- Обработчики сигналов ---
reload_ignore() {
  log INFO "Получен SIGUSR1 — пропускаем (Caddy сам перезагрузится)."
}
setup_signal_handlers() {
  trap reload_ignore USR1
  trap 'kill_all; log INFO "Все процессы остановлены."; exit 0' TERM INT QUIT
}

# --- Инициализация NSS DB ---
ensure_nss_db() {
  if [ ! -d /data/.pki/nssdb ]; then
    log INFO "Создаём NSS DB в /data/.pki/nssdb..."
    mkdir -p /data/.pki/nssdb
    certutil -N -d sql:/data/.pki/nssdb --empty-password
    log INFO "NSS DB готова."
  fi
  export NSS_DB_DIR=/data/.pki/nssdb
  export SSL_CERT_DIR=/etc/ssl/certs
  export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
}

# --- Цикл синхронизации PEM ---
start_pem_loop() {
  log INFO "Запуск цикла синхронизации PEM (каждые 30м)..."
  while :; do
    for d in "$CERT_DIR"/*/; do
      [ -d "$d" ] || continue
      domain=$(basename "$d")
      crt="$d/${domain}.crt"
      key="$d/${domain}.key"
      if [ -f "$crt" ] && [ -f "$key" ]; then
        cp "$crt" "$d/${domain}_fullchain.pem"
        cp "$key" "$d/${domain}_privkey.pem"
        chmod 600 "$d/"*.pem
        log INFO "[$domain] PEM обновлён."
      else
        log WARN "[$domain] .crt или .key не найдены, пропуск."
      fi
    done
    sleep 1800
  done
}

# --- Генерация сниппета (однократно) ---
generate_snippet() {
  log INFO "Обновление сниппета запрещённых CIDR..."
  # подготовка
  mkdir -p "$(dirname "$SNIPPET")"
  : > "$TMPFILE"

  # 1) загрузка всех списков в TMPFILE
  for url in $SNIPPET_URLS; do
    curl -fsSL "$url" >> "$TMPFILE" \
      || log WARN "Не удалось загрузить $url"
  done

  # 2) очистка TMPFILE: удалить комментарии и пустые строки, удалить хвосты после ';'
  sed -i \
    -e 's/#.*$//'         \
    -e '/^[[:space:]]*$/d'\
    -e '/^;/d'            \
    -e 's/;.*$//'         \
    "$TMPFILE"

  # 3) сортировка и дедуп
  sort -u "$TMPFILE" -o "$TMPFILE"

  # 4) генерация итогового сниппета
  {
    printf '(defender_bad_ranges) {\n'
    printf '    ranges'
    awk '{ printf " %s", $0 } END { printf "\n" }' "$TMPFILE"
    printf '}\n'
  } > "$SNIPPET"

  log INFO "Сниппет обновлён: $SNIPPET"
}

# --- Цикл генерации сниппета каждые 1ч ---
start_snippet_loop() {
  log INFO "Запуск цикла генерации сниппета (каждые 1ч)..."
  while :; do
    generate_snippet
    sleep 3600
  done
}

# --- Наблюдение за каталогом /etc/caddy ---
watch_config() {
  log INFO "Наблюдение за /etc/caddy ($WATCH_NAME)..."
  LAST=0
  inotifywait -m -e close_write -e moved_to --format '%w%f %e %T' --timefmt '%s' /etc/caddy \
    | while read -r file events timestamp; do
      now=$(date +%s)
      delta=$((now - LAST))
      log INFO "Событие $events на $file (Δ ${delta}s)"
      if [ "$delta" -lt "$CONFIG_COOLDOWN" ]; then
        log INFO "Активен таймаут ${CONFIG_COOLDOWN}s, пропуск перезагрузки."
        continue
      fi
      log INFO "Изменение обнаружено, проверка конфигурации..."
      [ "$ADAPTER" = "caddyfile" ] && caddy fmt --overwrite "$CONFIG_PATH"
      if caddy validate --config "$CONFIG_PATH" --adapter "$ADAPTER"; then
        caddy reload --config "$CONFIG_PATH" --adapter "$ADAPTER"
        log INFO "Caddy успешно перезагружен."
      else
        log ERROR "Ошибка валидации, перезагрузка отменена."
      fi
      LAST=$now
    done
}

# --- Запуск Caddy в фоне ---
run_caddy() {
  log INFO "Стартуем Caddy (foreground)..."
  caddy run --config "$CONFIG_PATH" --adapter "$ADAPTER" &
  add_pid $!
}

# --- Главная функция ---
main() {
  load_config
  setup_signal_handlers
  ensure_nss_db

  if [ "$SKIP_FUNCTIONAL" = "false" ]; then
    start_pem_loop &
    add_pid $!

    start_snippet_loop &
    add_pid $!

    watch_config &
    add_pid $!
  else
    log INFO "SKIP_FUNCTIONAL=true — запускаем только Caddy."
  fi

  run_caddy

  # Ждём завершения Caddy (ENTRYPOINT не завершится)
  wait
}

# --- Точка входа ---
main
