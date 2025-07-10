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
CLEAR_START=${CLEAR_START:-false}       # true — только запускаем Caddy, без лупов и watcher
LOGLEVEL=${LOGLEVEL:-INFO}                      # Уровень логирования (DEBUG|INFO|WARN|ERROR)

# snippet-параметры
TMPFILE=${TMPFILE:-/tmp/defender_cidrs.txt}                                             # Временный файл CIDR
DEFENDER_SNIPPET=${DEFENDER_SNIPPET:-/etc/caddy/defender_bad_ranges.caddy}                                # Итоговый сниппет
DEFENDER_SNIPPET_URLS=${DEFENDER_SNIPPET_URLS:-"\
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_level1.netset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/firehol_webclient.netset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/stopforumspam.ipset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/bds_atif.ipset \
https://raw.githubusercontent.com/firehol/blocklist-ipsets/master/stopforumspam_toxic.netset \
https://www.spamhaus.org/drop/drop.txt"}  # Список URL для обновления CIDR

# Crowdsec API
LAPI_URL=${LAPI_URL:-http://127.0.0.1:8080/v1}

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

random_html() {
    # === ПЕРЕМЕННЫЕ ===
    sitedir="${SITEDIR:-/srv}"
    temp_dir="${TMPDIR:-/tmp}"
    temp_extract="$temp_dir/random_html_tmp"
    repo_url="${TEMPLATE_REPO_URL:-https://github.com/GFW4Fun/randomfakehtml/archive/refs/heads/master.zip}"
    archive_name="${ARCHIVE_NAME:-master.zip}"
    extracted_dir="${EXTRACTED_DIR:-randomfakehtml-master}"
    extracted_path="$temp_extract/$extracted_dir"

    unzip_cmd="${UNZIP_CMD:-unzip -q}"
    wget_cmd="${WGET_CMD:-wget -q}"
    rm_cmd="${RM_CMD:-rm -rf}"
    cp_cmd="${CP_CMD:-cp -a}"

    # === ПОДГОТОВКА ВРЕМЕННОЙ ДИРЕКТОРИИ ===
    $rm_cmd "$temp_extract" >/dev/null 2>&1 || true
    mkdir -p "$temp_extract" || {
        log "ERROR" "Не удалось создать временную директорию: $temp_extract"
        return 0
    }

    archive_path="$temp_extract/$archive_name"

    # === ЗАГРУЗКА И РАСПАКОВКА ===
    $wget_cmd "$repo_url" -O "$archive_path"
    $unzip_cmd "$archive_path" -d "$temp_extract"
    $rm_cmd "$archive_path"

    if [ ! -d "$extracted_path" ]; then
        log "ERROR" "Извлечённая директория не найдена: $extracted_path"
        return 0
    fi

    # === ПОИСК ШАБЛОНОВ ===
    template_dirs=""
    for d in "$extracted_path"/*; do
        [ -d "$d" ] && [ "$(basename "$d")" != "assets" ] && template_dirs="$template_dirs $d"
    done

    if [ -z "$template_dirs" ]; then
        log "ERROR" "Шаблоны не найдены в $extracted_path"
        return 0
    fi

    # === ВЫБОР СЛУЧАЙНОГО ШАБЛОНА ===
    set -- $template_dirs
    count=$#
    rand_index=$(awk -v max="$count" 'BEGIN { srand(); print int(rand() * max) + 1 }')
    i=1
    for path in "$@"; do
        [ "$i" -eq "$rand_index" ] && selected_template="$path" && break
        i=$((i + 1))
    done

    log "INFO" "Выбран шаблон: $(basename "$selected_template")"

    # === ПОДГОТОВКА КАТАЛОГА НАЗНАЧЕНИЯ ===
    if [ -d "$sitedir" ]; then
        $rm_cmd "$sitedir"/* "$sitedir"/.[!.]* "$sitedir"/..?* 2>/dev/null || true
    else
        mkdir -p "$sitedir" || {
            log "ERROR" "Не удалось создать каталог назначения: $sitedir"
            return 0
        }
    fi

    # === КОПИРОВАНИЕ ШАБЛОНА ===
    $cp_cmd "$selected_template/." "$sitedir"
}

upstream_healthcheck_loop() {
  local interval="${HEALTHCHECK_INTERVAL:-300}"         # Интервал между проверками
  local timeout="${HEALTHCHECK_TIMEOUT:-30}"            # Таймаут curl
  local max_fails="${HEALTHCHECK_MAX_FAILURES:-3}"      # Порог "fails"
  local url="${HEALTHCHECK_URL:-http://localhost:2019/reverse_proxy/upstreams}"
  local initial_delay="${HEALTHCHECK_INITIAL_DELAY:-60}"  # Задержка перед первой проверкой

  log INFO "Старт healthcheck upstream'ов Caddy: $url (через ${initial_delay}s, затем каждые ${interval}s, порог фейлов: $max_fails)..."

  sleep "$initial_delay"

  while :; do
    if ! output=$(curl -sf --max-time "$timeout" "$url"); then
      log ERROR "Healthcheck: не удалось получить данные от API Caddy ($url). Перезапуск."
      kill 1
    fi

    fails=$(printf '%s\n' "$output" | grep -o '"fails":[0-9]*' | cut -d: -f2)

    for count in $fails; do
      if [ "$count" -ge "$max_fails" ]; then
        log ERROR "Healthcheck: обнаружен upstream с fails=$count (порог $max_fails). Перезапуск."
        kill 1
      fi
    done

    log DEBUG "Healthcheck: все upstream'ы в норме (fails: $fails)"
    sleep "$interval"
  done
}

# --- Главная функция ---
main() {
  load_config
  setup_signal_handlers
  ensure_nss_db

  if [ "$CLEAR_START" = "false" ]; then
      start_pem_loop & add_pid $!
      watch_config & add_pid $!
      upstream_healthcheck_loop & add_pid $!
  else
      log INFO "CLEAR_START=true — only starting Caddy."
  fi

  if [ ! -f /srv/index.html ]; then
    random_html
  fi

  run_caddy
  wait
}

# --- Точка входа ---
main
