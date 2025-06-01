#!/bin/sh

# === Handle SIGTERM for graceful shutdown ===
trap 'echo "[INFO] Caught SIGTERM. Stopping x-ui..."; exit 0' SIGTERM

# === Execute all *.sh scripts in /mnt/sh ===
if [ -d "/mnt/sh" ]; then
  echo "[INFO] Detected /mnt/sh directory. Applying permissions..."
  chmod -R 777 /mnt/sh

  echo "[INFO] Searching for scripts in /mnt/sh..."
  find /mnt/sh -type f -name "*.sh" -print0 | sort -z | while IFS= read -r -d '' script; do
    echo "[INFO] Executing script: $script"
    sh "$script"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Script failed: $script. Aborting startup."
      exit 1
    fi
  done

  echo "[INFO] All scripts in /mnt/sh executed successfully."
fi

# === Copy binaries from /mnt/bin to /app/bin ===
if [ -d "/mnt/bin" ]; then
  echo "[INFO] Detected /mnt/bin directory. Copying contents to /app/bin..."
  if ! cp -r /mnt/bin/* /app/bin/; then
    echo "[ERROR] Failed to copy from /mnt/bin to /app/bin. Aborting startup."
    exit 1
  fi
  echo "[INFO] Binaries copied to /app/bin successfully."
fi

# === Launch main application ===
echo "[INFO] Launching x-ui..."
exec /app/x-ui
