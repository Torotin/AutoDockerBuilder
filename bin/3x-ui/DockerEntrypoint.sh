#!/usr/bin/env bash
# entrypoint.sh � ����� ����� Docker-���������� ��� x-ui
# ��������:
#   1) ������������ SIGTERM ��� ����������� ����������
#   2) ��������� ��� ������� �� /mnt/sh/beforestart ����� ������� ��������� ����������
#   3) �������� ��������� �� /mnt/bin � /app/bin
#   4) ��������� x-ui � ����, ��������� ��� PID
#   5) ����� ���� ��� x-ui ���������, ��������� ������� �� /mnt/sh/afterstart
#   6) ��� ���������� x-ui ��� ������� �� �������

set -euo pipefail

###############################################################################
# 1) ��������� SIGTERM ��� graceful shutdown
###############################################################################
# ��� ��������� SIGTERM ���������� ��������� ���������� �������� ������� (x-ui)
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
# 2) ���������� �������� �� /mnt/sh/beforestart
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
# 3) ����������� ���������� �� /mnt/bin � /app/bin
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
# 4) ������ ��������� ���������� x-ui � ����
###############################################################################
echo "[INFO] Launching x-ui in background..."
/app/x-ui &
XUI_PID=$!
echo "[INFO] x-ui PID is $XUI_PID."

# �������� ��������� �����, ����� ���������� ������ �������� ����� afterstart
sleep 10

###############################################################################
# 5) ���������� �������� �� /mnt/sh/afterstart ����� ������ x-ui
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
      # ������������� x-ui, ���� afterstart-������ ���������� � �������
      kill -TERM "$XUI_PID" 2>/dev/null || true
      wait "$XUI_PID"
      exit 1
    fi
  done

  echo "[INFO] All scripts in /mnt/sh/afterstart executed successfully."
fi

###############################################################################
# 6) �������� ���������� x-ui (��� �������)
###############################################################################
echo "[INFO] Waiting for x-ui (PID $XUI_PID) to exit..."
wait "$XUI_PID"
EXIT_CODE=$?
echo "[INFO] x-ui exited with code $EXIT_CODE."
exit "$EXIT_CODE"
