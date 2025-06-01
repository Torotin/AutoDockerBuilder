#!/usr/bin/env bash
# entrypoint.sh — точка входа Docker-контейнера для x-ui
# Описание:
#   1) Обрабатываем SIGTERM для корректного завершения
#   2) Запускаем все скрипты из /mnt/sh/beforestart перед стартом основного приложения
#   3) Копируем бинарники из /mnt/bin в /app/bin
#   4) Запускаем x-ui в фоне, сохраняем его PID
#   5) После того как x-ui стартовал, выполняем скрипты из /mnt/sh/afterstart
#   6) Ждём завершения x-ui или сигнала от системы

set -euo pipefail

###############################################################################
# 1) Обработка SIGTERM для graceful shutdown
###############################################################################
# При получении SIGTERM необходимо корректно остановить дочерний процесс (x-ui)
term_handler() {
  echo "[INFO] Caught SIGTERM. Stopping x-ui..."
  if [[ -n "${XUI_PID:-}" ]]; then
    kill -TERM "$XUI_PID" 2>/dev/null || true
    wait "$XUI_PID"
  fi
  echo "[INFO] x-ui stopped."
  exit 0
}
trap 'term_handler' SIGTERM

###############################################################################
# 2) Выполнение скриптов из /mnt/sh/beforestart
###############################################################################
if [ -d "/mnt/sh/beforestart" ]; then
  echo "[INFO] Detected /mnt/sh/beforestart directory. Applying permissions..."
  chmod -R 777 /mnt/sh/beforestart

  echo "[INFO] Searching for scripts in /mnt/sh/beforestart..."
  find /mnt/sh/beforestart -type f -name "*.sh" -print0 | sort -z | while IFS= read -r -d '' script; do
    echo "[INFO] Executing script: $script"
    sh "$script"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Script failed: $script. Aborting startup."
      exit 1
    fi
  done

  echo "[INFO] All scripts in /mnt/sh/beforestart executed successfully."
fi

###############################################################################
# 3) Копирование бинарников из /mnt/bin в /app/bin
###############################################################################
if [ -d "/mnt/bin" ]; then
  echo "[INFO] Detected /mnt/bin directory. Copying contents to /app/bin..."
  if ! cp -r /mnt/bin/* /app/bin/; then
    echo "[ERROR] Failed to copy from /mnt/bin to /app/bin. Aborting startup."
    exit 1
  fi
  echo "[INFO] Binaries copied to /app/bin successfully."
fi

###############################################################################
# 4) Запуск основного приложения x-ui в фоне
###############################################################################
echo "[INFO] Launching x-ui in background..."
/app/x-ui &
XUI_PID=$!
echo "[INFO] x-ui PID is $XUI_PID."

# Создадим небольшую паузу, чтобы обеспечить запуск процесса перед afterstart
sleep 10

###############################################################################
# 5) Выполнение скриптов из /mnt/sh/afterstart после старта x-ui
###############################################################################
if [ -d "/mnt/sh/afterstart" ]; then
  echo "[INFO] Detected /mnt/sh/afterstart directory. Applying permissions..."
  chmod -R 777 /mnt/sh/afterstart

  echo "[INFO] Searching for scripts in /mnt/sh/afterstart..."
  find /mnt/sh/afterstart -type f -name "*.sh" -print0 | sort -z | while IFS= read -r -d '' script; do
    echo "[INFO] Executing script: $script"
    sh "$script"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Script failed: $script. Aborting startup."
      # Останавливаем x-ui, если afterstart-скрипт завершился с ошибкой
      kill -TERM "$XUI_PID" 2>/dev/null || true
      wait "$XUI_PID"
      exit 1
    fi
  done

  echo "[INFO] All scripts in /mnt/sh/afterstart executed successfully."
fi

###############################################################################
# 6) Ожидание завершения x-ui (или сигнала)
###############################################################################
echo "[INFO] Waiting for x-ui (PID $XUI_PID) to exit..."
wait "$XUI_PID"
EXIT_CODE=$?
echo "[INFO] x-ui exited with code $EXIT_CODE."
exit "$EXIT_CODE"
