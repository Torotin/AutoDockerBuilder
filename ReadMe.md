[![3x-ui-Docker-SelfHosted](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/3x-ui-Docker-selfhosted.yml/badge.svg)](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/3x-ui-Docker-selfhosted.yml)
[![Caddy-L4 Docker Self-Hosted](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/Caddy-L4-Docker-selfhosted.yml/badge.svg)](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/Caddy-L4-Docker-selfhosted.yml)
[![warp-plus-Docker-Selfhosted](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/WarpPlus-Docker-Selfhosted.yml/badge.svg)](https://github.com/Torotin/AutoDockerBuilder/actions/workflows/WarpPlus-Docker-Selfhosted.yml)


---


# 🐳 Docker Workflow Generator

Этот репозиторий содержит универсальный шаблон GitHub Actions workflow для автоматической сборки и публикации Docker-образов из внешних репозиториев. Настройка осуществляется через переменные в `.envsubst-vars`, генерация — с помощью `generate-workflow.sh`.

## 📁 Структура проекта

```markdown

├── ReadMe.md                      # Этот файл
├── docker-workflow-template.yaml  # Шаблон GitHub Actions (workflow)
├── generate-workflow.sh           # Скрипт генерации *.yml из шаблона
├── .envsubst-vars                 # Переменные окружения для шаблона
├── bin/                           # Кастомные Docker-файлы для каждого проекта
├── 3x-ui/
│   ├── dockerfile
│   ├── DockerEntrypoint.sh
│   └── DockerInit.sh
├── caddy/
│   ├── dockerfile
│   └── DockerEntrypoint.sh
├── warp/
├────── Dockerfile
├────── DockerEntrypoint.sh
├────── config.json.template
└────── warp.py

```

## ⚙️ Как использовать

1. **Настрой `.envsubst-vars`**  
   Укажи переменные проекта (название, ссылки, пути, кастомные файлы):

   ```env
   PROJECT_NAME=warp-plus
   REPO_EXT_URL=https://github.com/bepass-org/warp-plus.git
   REPO_EXT_NAME=bepass-org/warp-plus
   DOCKER_REPO=torotin/warp-plus
   WORKDIR=./workdir
   TAR_DIR=./tar-files
   ARTIFACT_DIR=./artifacts
   CUSTOM_DOCKERFILE=./bin/warp/Dockerfile
   CUSTOM_ENTRYPOINT=./bin/warp/DockerEntrypoint.sh
   CUSTOM_INIT=./bin/warp/DockerInit.sh
   CUSTOM_CONFIG=./bin/warp/config.json.template
   CRON_SCHEDULE=0 4 * * *
   CUSTOM_FILES_GLOB=bin/warp/**
    ````

2. **Запусти генератор:**

   ```bash
   ./generate-workflow.sh
   ```

   В результате будет создан файл:

   ```
   .github/workflows/warp-plus-Docker-Selfhosted.yml
   ```

3. **Закоммить и запушь:**

   ```bash
   git add .github/workflows/warp-plus-Docker-Selfhosted.yml
   git commit -m "Добавлен workflow для warp-plus"
   git push
   ```

## 🛠 Поддерживаемые функции шаблона

* Тригер по `workflow_dispatch`, `push`, `cron`
* Опции `build_amd64`, `build_arm64`, `build_386`
* Пропуск/форсировка сборки: `build_skip`, `build_force`
* Отдельный этап `release` с GitHub Release + DockerHub + `.tar.gz`
* Поддержка кастомных Dockerfile/entrypoint/init/config
* Кэширование buildx по платформам
* Очистка старых workflow-запусков

## 💡 Подсказки

* Для генерации нескольких workflow просто создавай отдельные `.envsubst-vars` и дублируй `generate-workflow.sh` с параметром:

  ```bash
  VARS_FILE=".envsubst-vars-3xui" ./generate-workflow.sh
  ```

* Переменные подставляются через `envsubst`. Только `${...}`-стиль.

## 🧪 Пример CI-CD

```yaml
on:
  push:
    paths:
      - '.github/workflows/warp-plus-Docker-Selfhosted.yml'
      - 'bin/warp/**'
```

* Автоматически триггерит при изменении `bin/warp` или самого `.yml`
* Вы можете использовать флаг `release_skip` для тестов без публикации

## 📦 Зависимости

* `envsubst` (часть `gettext`)
* `bash`, `coreutils`, `curl`, `jq`, `tree`
* Docker, Buildx, QEMU
