#!/usr/bin/env sh
set -euo pipefail

# ----------------------------------------
# DockerEntrypoint.sh for Caddy with live
# config reload and PEM auto-sync loop
# ----------------------------------------

# Cooldown (seconds) between reload attempts
CONFIG_COOLDOWN=${CONFIG_COOLDOWN:-5}

# ACME certs root directory
CERT_DIR="${CERT_DIR:-/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory}"

## Determine config type (Caddyfile vs JSON)
if [ "${USE_JSON:-false}" = "true" ]; then
  CONFIG_PATH="/etc/caddy/config.json"
  ADAPTER="json"
  WATCH_NAME="JSON config"
else
  CONFIG_PATH="/etc/caddy/Caddyfile"
  ADAPTER="caddyfile"
  WATCH_NAME="Caddyfile"
fi

# PIDs of background processes
PEM_PID=""
WATCH_PID=""
CADDY_PID=""

# Cleanup function on container shutdown
cleanup() {
  echo "[🛑] Shutting down..."
  [ -n "$PEM_PID" ]   && kill "$PEM_PID"   2>/dev/null || true
  [ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null || true
  [ -n "$CADDY_PID" ] && kill -TERM "$CADDY_PID" 2>/dev/null || true
  wait
  echo "[🛑] All stopped."
  exit 0
}

# Ignore SIGUSR1 (Caddy reload) in this script
reload_ignore() {
  echo "[🔄] Got SIGUSR1 (reload), ignoring at entrypoint."
}
trap reload_ignore USR1

# On SIGTERM, SIGINT, SIGQUIT — full cleanup
trap cleanup TERM INT QUIT

# Loop: copy *.crt/ *.key → fullchain.pem + privkey.pem
start_pem_loop() {
  echo "[🔁] Starting PEM sync loop (every 30m)..."
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
        echo "[✅] [$domain] PEM updated."
      else
        echo "[⚠️] [$domain] Missing .crt/.key, skipping."
      fi
    done
    sleep 1800
  done
}

# Loop: watch config for changes and reload Caddy
watch_config() {
  echo "[🔁] Watching $WATCH_NAME for changes..."
  LAST=0
  # Запускаем inotifywait в режиме постоянного слежения и передаём его вывод на stdin цикла
  inotifywait -m -e close_write -e moved_to --format '%w%f %e %T' --timefmt '%H:%M:%S' "$CONFIG_PATH" \
  | while read -r file events timestamp; do
      now=$(date +%s)
      delta=$((now - LAST))
      echo "[🐛] Event $events on $file at $timestamp (Δ ${delta}s)"

      # Если ещё не прошёл CONFIG_COOLDOWN
      if [ "$delta" -lt "$CONFIG_COOLDOWN" ]; then
        echo "[⏱] Cooldown active (${CONFIG_COOLDOWN}s), skipping reload."
        continue
      fi

      echo "[🛠] Change detected, validating..."
      [ "$ADAPTER" = "caddyfile" ] && caddy fmt --overwrite "$CONFIG_PATH"
      if caddy validate --config "$CONFIG_PATH" --adapter "$ADAPTER"; then
        caddy reload --config "$CONFIG_PATH" --adapter "$ADAPTER"
        echo "[🔄] Caddy reloaded."
      else
        echo "[⚠️] Validation failed, no reload."
      fi

      LAST=$now
    done
}


# Initialize NSS DB in /data
if [ ! -d "/data/.pki/nssdb" ]; then
  echo "[+] Creating NSS DB at /data/.pki/nssdb..."
  mkdir -p /data/.pki/nssdb
  certutil -N -d sql:/data/.pki/nssdb --empty-password
  echo "[✓] NSS DB ready."
fi

export SSL_CERT_DIR=/etc/ssl/certs
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export NSS_DB_DIR=/data/.pki/nssdb

echo "[🚀] Starting services..."

# Start PEM-sync loop
start_pem_loop &
PEM_PID=$!

# Start config watcher
watch_config &
WATCH_PID=$!

# Run Caddy in foreground (so SIGUSR1 only hits Caddy)
caddy run --config "$CONFIG_PATH" --adapter "$ADAPTER" &
CADDY_PID=$!

# Wait for Caddy to exit
wait "$CADDY_PID"
