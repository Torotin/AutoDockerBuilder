#!/bin/sh
set -e

HAPROXY_CFG="${HAPROXY_CFG:-/usr/local/etc/haproxy/haproxy.cfg}"
HAPROXY_PID="/var/run/haproxy.pid"

start_haproxy() {
    # Стартуем haproxy в master-worker режиме и пишем PID
    haproxy -W -db -f "$HAPROXY_CFG" -p "$HAPROXY_PID" &
    export HAPROXY_MAIN_PID=$!
}

reload_haproxy() {
    if [ -f "$HAPROXY_PID" ]; then
        echo "Reloading haproxy (pid $(cat "$HAPROXY_PID")) ..."
        kill -USR2 "$(cat "$HAPROXY_PID")"
    else
        echo "Haproxy pidfile not found, starting..."
        start_haproxy
    fi
}

# Если запускаем с аргументами, не связанными с haproxy — передаём как есть
if [ "${1#-}" != "$1" ] || [ "$1" = "haproxy" ]; then
    # Запускаем haproxy
    start_haproxy

    # Следим за изменениями конфигурации
    while true; do
        # Следим только за изменением содержимого (write/close)
        inotifywait -e close_write "$HAPROXY_CFG"
        echo "haproxy.cfg changed, reloading..."
        reload_haproxy
    done
else
    exec "$@"
fi
