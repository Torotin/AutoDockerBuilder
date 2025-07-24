#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# === 📦 Настройки ===
TEMPLATE_FILE="docker-workflow-template.yaml"
VARS_FILE="./.envsubst-vars"
OUTPUT_DIR=".github/workflows"

# === 🔍 Проверка наличия шаблона и переменных ===
[[ ! -f "$TEMPLATE_FILE" ]] && { echo "❌ Не найден шаблон: $TEMPLATE_FILE"; exit 1; }
[[ ! -f "$VARS_FILE" ]] && { echo "❌ Не найден файл переменных: $VARS_FILE"; exit 1; }

# === 📥 Загрузка переменных из .envsubst-vars ===
set -a
. "$VARS_FILE"
set +a

# === 📄 Проверка обязательных переменных ===
: "${PROJECT_NAME:?❌ PROJECT_NAME не задан}"
: "${REPO_EXT_URL:?❌ REPO_EXT_URL не задан}"
: "${DOCKER_REPO:?❌ DOCKER_REPO не задан}"

# === 🧾 Генерация итогового файла ===
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}-Docker-Selfhosted.yml"
mkdir -p "$OUTPUT_DIR"

envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# === ✅ Результат ===
echo ""
echo "✅ Workflow успешно сгенерирован: $OUTPUT_FILE"