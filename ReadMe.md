# Генератор GitHub Actions Workflow для Docker Self-hosted

## Описание

`generate-workflow.sh` создаёт GitHub Actions workflow на основе шаблона `docker-workflow-template.yaml` и переменных из файла `.envsubst-vars`. Итоговый файл помещается в `.github/workflows/${PROJECT_NAME}-Docker-Selfhosted.yml`.

## Требования

* Bash (≥ 4) с поддержкой `envsubst` (часть GNU coreutils)
* Файл шаблона `docker-workflow-template.yaml`
* Файл переменных `.envsubst-vars`
* Права на запись в папку `.github/workflows`

## Установка и настройка

1. Склонируйте репозиторий и перейдите в его корень.
2. Сделайте скрипт исполняемым:

   ```bash
   chmod +x generate-workflow.sh
   ```
3. Создайте файл `.envsubst-vars` в корне проекта и задайте в нём необходимые переменные.

## Конфигурация переменных

```bash
# .envsubst-vars
PROJECT_NAME=имя_проекта               # используется в имени workflow и тегах
REPO_EXT_URL=https://…/repo.git        # URL внешнего репозитория для клонирования
REPO_EXT_NAME=owner/repo               # owner/repo для обращения к GitHub API
DOCKER_REPO=user/имя                   # Docker Hub репозиторий
WORKDIR=external                       # папка для клонирования внешнего репо
TAR_DIR=tarballs                       # куда сохранять tar-архивы
ARTIFACT_DIR=artifacts                 # куда складывать вспомогательные файлы
CUSTOM_FILES_GLOB="Dockerfile*,…"      # glob для отслеживания изменений
CUSTOM_DOCKERFILE=custom/Dockerfile    # при необходимости замены Dockerfile
CUSTOM_ENTRYPOINT=custom/entrypoint.sh
CUSTOM_INIT=custom/init.sh
CUSTOM_CONFIG=custom/config.yaml
CRON_SCHEDULE="0 0 * * *"              # cron-выражение для триггера schedule
```

## Использование

```bash
./generate-workflow.sh
```

Что делает скрипт:

1. Проверяет наличие шаблона и файла переменных.
2. Загружает и экспортирует переменные окружения.
3. Убеждается, что обязательные переменные заданы.
4. Прогоняет `envsubst` по шаблону и сохраняет результат в `.github/workflows/${PROJECT_NAME}-Docker-Selfhosted.yml`.
5. Выводит путь к сгенерированному файлу.

## Структура шаблона

* **on**

  * `workflow_dispatch` с флагами для управления сборкой и выпуском
  * `push` по изменениям workflow и кастомных файлов
  * `schedule` по cron
* **env** — все ключевые переменные передаются в рабочие шаги
* **jobs**

  * `prepare` — очистка, установка зависимостей, получение последнего тега, логика пропуска сборки
  * `build` — мультиплатформенная сборка и пуш через Buildx
  * `release` — сохранение образа в архив, генерация GitHub Release, очистка старых запусков

## Пример

```bash
# .envsubst-vars
PROJECT_NAME=myapp
REPO_EXT_URL=https://github.com/example/external-repo.git
REPO_EXT_NAME=example/external-repo
DOCKER_REPO=example/myapp
WORKDIR=external
TAR_DIR=tarballs
ARTIFACT_DIR=artifacts
CUSTOM_FILES_GLOB="Dockerfile*"
CUSTOM_DOCKERFILE=custom/Dockerfile
CUSTOM_ENTRYPOINT=custom/entrypoint.sh
CUSTOM_INIT=custom/init.sh
CUSTOM_CONFIG=custom/config.yaml
CRON_SCHEDULE="30 3 * * *"
```

Запуск:

```bash
./generate-workflow.sh
```

Результат:
`.github/workflows/myapp-Docker-Selfhosted.yml`
