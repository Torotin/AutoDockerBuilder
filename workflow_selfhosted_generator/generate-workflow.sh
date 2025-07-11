#!/usr/bin/env bash
set -e

# === Настройки ===
TEMPLATE_FILE="docker-workflow-template.yaml"
VARS_FILE=".envsubst-vars"
OUTPUT_DIR=".github/workflows"

# Проверка файлов
[ ! -f "$TEMPLATE_FILE" ] && { echo "❌ Не найден шаблон: $TEMPLATE_FILE"; exit 1; }
[ ! -f "$VARS_FILE" ] && { echo "❌ Не найден файл переменных: $VARS_FILE"; exit 1; }

# Загрузка переменных
export $(grep -v '^#' "$VARS_FILE" | xargs)

# Генерация имени финального файла
OUTPUT_FILE="$OUTPUT_DIR/${PROJECT_NAME}-Docker-Selfhosted.yml"
mkdir -p "$OUTPUT_DIR"

# Подстановка и сохранение
envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"

echo "✅ Workflow успешно сгенерирован: $OUTPUT_FILE"