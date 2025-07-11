## 📦 Docker Workflow Generator

Этот репозиторий содержит шаблон GitHub Actions workflow и Bash-генератор для автоматической сборки Docker multi-arch образов на self-hosted runner’ах.

### 🗂 Структура

```text
.
├── generate-workflow.sh          # Bash-скрипт для генерации workflow
├── docker-workflow-template.yaml # Шаблон workflow с переменными ${...}
├── .envsubst-vars                # Переменные окружения для подстановки
└── .github/
    └── workflows/
        └── <сгенерированный>.yml # Финальный workflow
```

---

### ⚙️ Установка и запуск

1. Отредактируй переменные под свой проект в `.envsubst-vars`:

```env
PROJECT_NAME=warp-plus
REPO_EXT_URL=https://github.com/youruser/warp-plus.git
REPO_EXT_NAME=youruser/warp-plus
DOCKER_REPO=yourdockerhub/warp-plus
WORKDIR=./workdir
TAR_DIR=./tar-files
ARTIFACT_DIR=./artifacts
CUSTOM_DOCKERFILE=./bin/warp-plus/dockerfile
CUSTOM_ENTRYPOINT=./bin/warp-plus/DockerEntrypoint.sh
CUSTOM_INIT=./bin/warp-plus/DockerInit.sh
CRON_SCHEDULE=0 4 * * *
CUSTOM_FILES_GLOB=bin/warp-plus/**
```

2. Сделай скрипт исполняемым и запусти:

```bash
chmod +x generate-workflow.sh
./generate-workflow.sh
```

---

### 📄 Что будет создано

Скрипт сгенерирует готовый `.yml` файл GitHub Actions и положит его в:

```bash
.github/workflows/<PROJECT_NAME>-Docker-Selfhosted.yml
```

---

### 🔁 Повторное использование

Чтобы создать workflow для другого проекта:

* скопируй `.envsubst-vars` и измени значения
* перезапусти `./generate-workflow.sh`

---

### 📌 Требования

* `bash`
* `envsubst` (входит в пакет `gettext`)
* self-hosted runner с Docker + Buildx + QEMU
