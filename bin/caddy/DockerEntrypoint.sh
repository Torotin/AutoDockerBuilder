#!/usr/bin/env sh
set -euo pipefail

# ----------------------------------------
# DockerEntrypoint.sh для Caddy
# POSIX‐совместимый, Alpine Linux
# Live‐reload и автоматическая синхронизация PEM
# ----------------------------------------

# --- Параметры окружения (с значениями по умолчанию) ---
CONFIG_COOLDOWN=${CONFIG_COOLDOWN:-5}          # Пауза между перезагрузками (сек)
CERT_DIR=${CERT_DIR:-/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory}  # Корень ACME-сертификатов
USE_JSON=${USE_JSON:-false}                    # Использовать JSON-конфиг вместо Caddyfile
SKIP_FUNCTIONAL=${SKIP_FUNCTIONAL:-false}      # Если true — только запускаем Caddy, без лупов и watcher

# --- Глобальные переменные (дальнейшая инициализация) ---
PIDS=""                                       # Список PID фоновых задач
CONFIG_PATH=                                  # Путь к конфигу (устанавливается в load_config)
ADAPTER=                                      # Адаптер caddy (json|caddyfile)
WATCH_NAME=                                   # Для логов

# --- Функция логирования ---
log() {
  level=$1; shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
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

# --- Главная функция ---
main() {
  load_config
  setup_signal_handlers
  ensure_nss_db

  if [ "$SKIP_FUNCTIONAL" = "false" ]; then
    start_pem_loop &
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
