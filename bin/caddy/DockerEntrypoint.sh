#!/usr/bin/env sh
set -euo pipefail

COOLDOWN=2  # секунда
# Корневая папка для ACME-сертификатов
CERT_DIR="${CERT_DIR:-/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory}"

# Путь и адаптер конфиг-файла
if [ "${USE_JSON:-false}" = "true" ]; then
  CONFIG_PATH="/etc/caddy/config.json"
  ADAPTER="json"
  WATCH_NAME="JSON config"
else
  CONFIG_PATH="/etc/caddy/Caddyfile"
  ADAPTER="caddyfile"
  WATCH_NAME="Caddyfile"
fi

# Пиды фоновых задач
PEM_PID=""
WATCH_PID=""
MAIN_PID=""

cleanup() {
  echo "[🛑] Shutting down..."
  [ -n "$PEM_PID" ]   && kill "$PEM_PID" 2>/dev/null || true
  [ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null || true
  [ -n "$MAIN_PID" ]  && kill -TERM "$MAIN_PID" 2>/dev/null || true
  wait
  echo "[🛑] Done."
  exit 0
}
trap cleanup TERM INT

start_pem_loop() {
  echo "[🔁] Starting multi-domain PEM loop (root: $CERT_DIR)..."
  while :; do
    for d in "$CERT_DIR"/*/; do
      [ -d "$d" ] || continue
      domain=$(basename "$d")
      crt="$d/${domain}.crt"
      key="$d/${domain}.key"
      out="$d"
      if [ -f "$crt" ] && [ -f "$key" ]; then
        mkdir -p "$out"
        cp -f "$crt" "$out/fullchain.pem"
        cp -f "$key" "$out/privkey.pem"
        chmod 600 "$out/"*.pem
        echo "[✅] [$domain] PEM updated."
      else
        echo "[⚠️] [$domain] .crt/.key missing, skip."
      fi
    done
    sleep 1800
  done
}

watch_config() {
  echo "[🔁] Watching $WATCH_NAME for changes..."
  # сразу же логируем стартовый timestamp
  LAST=$(date +%s)
  while inotifywait -m -e close_write -e moved_to --format '%w%f %e' "$CONFIG_PATH"; do
    now=$(date +%s)
    echo "[🐛] Event caught at $(date +%T), seconds since last: $((now - LAST))"
    # если хотите совсем без задержки, поставьте COOLDOWN=0
    if [ $((now - LAST)) -lt $COOLDOWN ]; then
      echo "[⏱] Cooldown ($COOLDOWN s); skipping."
      continue
    fi

    echo "[🛠] Change detected in $WATCH_NAME, validating..."
    if [ "$ADAPTER" = "caddyfile" ]; then
      caddy fmt --overwrite "$CONFIG_PATH"
    fi
    if caddy validate --config "$CONFIG_PATH" --adapter "$ADAPTER"; then
      caddy reload --config "$CONFIG_PATH" --adapter "$ADAPTER"
      echo "[🔄] Caddy reloaded ($ADAPTER)."
    else
      echo "[⚠️] Validation failed, skipping reload."
      caddy validate --config "$CONFIG_PATH" --adapter "$ADAPTER" 2>&1
    fi
    LAST=$now
  done
}

# NSS DB — однажды в /data
if [ ! -d "/data/.pki/nssdb" ]; then
  echo "[+] Creating NSS database in /data/.pki/nssdb..."
  mkdir -p /data/.pki/nssdb
  certutil -N -d sql:/data/.pki/nssdb --empty-password
  echo "[✓] NSS DB ready."
fi
export SSL_CERT_DIR=/etc/ssl/certs
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export NSS_DB_DIR=/data/.pki/nssdb

echo "[🚀] Launching Caddy ($ADAPTER adapter)..."
exec caddy run \
  --config "$CONFIG_PATH" \
  --adapter "$ADAPTER" &

MAIN_PID=$!

# Фоновые задачи
start_pem_loop &
PEM_PID=$!

watch_config &
WATCH_PID=$!

# Ожидаем завершения Caddy
wait "$MAIN_PID"