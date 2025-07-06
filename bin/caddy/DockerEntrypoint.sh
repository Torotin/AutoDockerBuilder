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
KEY_FILE=/etc/caddy/crowdsec_api_key
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

# --- Генерация сниппета (однократно) ---
generate_snippets_defender() {
  log INFO "Обновление всех сниппетов CIDR по каждому источнику..."
  set +e

  DEFENDER_SNIPPET_DIR=/etc/caddy/snippets/defender
  mkdir -p "$DEFENDER_SNIPPET_DIR"
  # Преобразуем DEFENDER_SNIPPET_URLS в список строк
  DEFENDER_URLS_LIST=$(printf '%s\n' "$DEFENDER_SNIPPET_URLS" | sed '/^[[:space:]]*$/d')
  total_expected=$(printf '%s\n' "$DEFENDER_URLS_LIST" | wc -l | tr -d ' ')

  processed=0
  for url in $DEFENDER_SNIPPET_URLS; do
    processed=$((processed + 1))

    # вычисляем имена
    name=$(basename "$url" | sed 's/\..*$//')
    tmp="/tmp/defender_${name}.txt"
    snip="$DEFENDER_SNIPPET_DIR/${name}.caddy"

    log INFO "Источник $url → $snip"

    # 1) загрузка
    if ! curl -fsSL "$url" > "$tmp"; then
      log WARN "Не удалось загрузить $url, пропуск"
      continue
    fi

    # проверяем, что файл не пустой
    if [ ! -s "$tmp" ]; then
      log WARN "Файл $tmp пустой после загрузки, пропуск"
      continue
    fi
    
    # удаляем свой публичный IPv4/IPv6, если он есть (в форме с /32 и без)
    if [ -n "${PUBLIC_IPV4:-}" ]; then
      sed -i \
        -e "/^${PUBLIC_IPV4}$/d" \
        -e "/^${PUBLIC_IPV4}\/32$/d" \
        "$tmp"
    fi
    if [ -n "${PUBLIC_IPV6:-}" ]; then
      sed -i \
        -e "/^${PUBLIC_IPV6}$/d" \
        -e "/^${PUBLIC_IPV6}\/32$/d" \
        "$tmp"
    fi

    # 2) очистка
    sed -i \
      -e 's/#.*$//' \
      -e '/^[[:space:]]*$/d' \
      -e '/^;/d' \
      -e 's/;.*$//' \
      -e 's/^[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      "$tmp"

    # 3) сортировка + дедуп
    sort -u "$tmp" -o "$tmp"

    # 4) конверсия одиночных IPv4 → /32
    awk '
      /\// { print; next }
      /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $0 "/32"; next }
      { print }
    ' "$tmp" > "${tmp}.fixed" && mv "${tmp}.fixed" "$tmp"

    # 5) теперь фильтруем только корректные CIDR
    grep -E '/[0-9]+$' "$tmp" > "${tmp}.cidr"
    mv "${tmp}.cidr" "$tmp"

    # снова проверяем, что после фильтрации есть данные
    if [ ! -s "$tmp" ]; then
      log WARN "Нет валидных CIDR в $tmp, пропуск"
      continue
    fi

    # 5) создание директории для сниппета
    mkdir -p "$(dirname "$snip")"

    # 6) генерация сниппета
    {
      printf "(defender_bad_ranges_%s) {\n" "$name"
      printf "    ranges"
      awk '{ printf " %s", $0 } END { printf "\n" }' "$tmp"
      printf "}\n"
    } > "$snip"

    # проверяем, что сниппет создался и не пуст
    if [ -s "$snip" ]; then
      log INFO "✓ $snip обновлён ($(wc -l < "$tmp" | tr -d ' ') CIDR)"
    else
      log ERROR "Не удалось создать сниппет $snip"
    fi
  done

  log INFO "Обработано $processed из $total_expected URL"


    # 7) объединяющий сниппет
  master="/etc/caddy/snippets/defender_all_ranges.caddy"
  mkdir -p "$(dirname "$master")"
  {
    echo "# Объединённый сниппет — импорт всех отдельных"

    # Сначала файлы
    for f in /etc/caddy/snippets/defender/*.caddy; do
      echo "import $f"
    done

    echo    # пустая строка

    # Затем определение самого сниппета — каждую часть подключаем как snippet
    printf "(defender_all_ranges) {\n"
    for f in /etc/caddy/snippets/defender/*.caddy; do
      name=$(basename "$f" .caddy)
      printf "    import %s\n" "defender_bad_ranges_$name"
    done
    printf "}\n"
  } > "$master"

  if [ -s "$master" ]; then
    log INFO "✓ Объединяющий сниппет сгенерирован: $master"
  else
    log ERROR "Не удалось создать объединяющий сниппет $master"
  fi

  set -e

}


# --- Цикл генерации сниппета каждые 1ч ---
start_snippets_defender_loop() {
  log INFO "Запуск цикла генерации сниппета (каждые 1ч)..."
  while :; do
    generate_snippets_defender
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

crowdsec_key_check() {
  # Пропускаем, если отключено
  if [ "${CROWDSEC_ENABLED:-true}" != "true" ]; then
    log INFO "CROWDSEC_ENABLED=false — пропускаем проверку CrowdSec"
    return 0
  fi

  # Подготовка папки для ключа
  mkdir -p "$(dirname "$KEY_FILE")"

  # Ждём доступности LAPI (таймаут 60s)
  deadline=$((SECONDS + 60))
  until curl -sS -o /dev/null "${LAPI_URL}/health"; do
    [ $SECONDS -ge $deadline ] && {
      log ERROR "CrowdSec LAPI не отвечает в течение 60s, пропускаем"
      return 1
    }
    log WARN "Ожидание CrowdSec LAPI на ${LAPI_URL}/health..."
    sleep 2
  done

  # Если файл ключа есть и непустой — проверяем
  if [ -s "${KEY_FILE}" ]; then
    EXISTING_KEY=$(cat "${KEY_FILE}")
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "X-Api-Key: ${EXISTING_KEY}" \
      "${LAPI_URL}/bouncers")
    if [ "$STATUS" -eq 200 ]; then
      log INFO "Существующий API-ключ валиден (HTTP $STATUS)."
      export CROWDSEC_API_KEY="$EXISTING_KEY"
      return 0
    else
      log WARN "Старый ключ не валиден (HTTP $STATUS), запросим новый."
    fi
  else
    log INFO "API key file отсутствует или пуст — запросим новый."
  fi

  # Пытаемся получить новый ключ (до 3 попыток, backoff)
  attempts=0
  until [ $attempts -ge 3 ]; do
    RESPONSE=$(curl -sS -H "Content-Type: application/json" \
      -d '{"type":"http","name":"caddy"}' \
      "${LAPI_URL}/bouncers")
    NEW_KEY=$(printf '%s' "$RESPONSE" | jq -r '.apiKey // empty')

    if [ -n "$NEW_KEY" ]; then
      # Сохраняем и экспортируем
      echo "$NEW_KEY" > "$KEY_FILE"
      chmod 600 "$KEY_FILE"
      log INFO "Новый API-ключ сохранён в $KEY_FILE"
      export CROWDSEC_API_KEY="$NEW_KEY"
      return 0
    fi

    # Ошибка: логируем фрагмент ответа и ждём
    log ERROR "Не удалось получить API-ключ (попытка $((attempts+1))): ${RESPONSE:0:300}"
    attempts=$((attempts+1))
    sleep $((attempts * 5))
  done

  log ERROR "После $attempts попыток не удалось получить API-ключ CrowdSec."
  return 1
}

# --- Главная функция ---
main() {
    load_config
    setup_signal_handlers
    ensure_nss_db

    if [ "$CLEAR_START" = "false" ]; then
        crowdsec_key_check
        start_pem_loop & add_pid $!
        # start_snippets_defender_loop & add_pid $!
        watch_config & add_pid $!
    else
        log INFO "CLEAR_START=true — only starting Caddy."
    fi

    run_caddy
    wait
}

# --- Точка входа ---
main
