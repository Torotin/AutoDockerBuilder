# AutoDockerBuilder

Автоматическая сборка и публикация Docker-образов внешних проектов с помощью GitHub Actions и self‑hosted раннеров. Репозиторий ежедневно проверяет новые релизы апстримов, собирает образы (в т.ч. мульти‑арх), публикует их в Docker Hub и прикладывает артефакты к GitHub Release.

---

## Что собирается

Поддерживаются несколько проектов, каждый со своим workflow:

- Caddy L4 (upstream: caddyserver/caddy) → Docker Hub: `torotin/caddy-l4`
- Warp Plus (upstream: bepass-org/warp-plus) → Docker Hub: `torotin/warp-plus`
- 3x-ui (upstream: MHSanaei/3x-ui) → Docker Hub: `torotin/3x-ui`
- usque (upstream: Diniboy1123/usque) → Docker Hub: `torotin/usque`

Файлы для сборки (Dockerfile/entrypoint) для некоторых проектов лежат в `bin/*`.

---

## Как это работает

- Ежедневный оркестратор: `.github/workflows/daily-trigger.yml` по расписанию (03:00 UTC) последовательно запускает все сборочные workflow и ждёт их завершения.
- Определение версии: каждый workflow запрашивает последний tag из upstream Releases и формирует собственный tag в этом репозитории в формате `<name>_<upstreamTag>` (например, `Caddy-L4_v2.7.6`).
- Пропуск, если уже собрано: если такой tag уже есть — сборка пропускается (если не принудительно).
- Сборка и публикация:
  - Сборка для выбранных платформ (по умолчанию чаще всего `linux/amd64`, при ручном запуске можно включать `arm64/v8`, `386`).
  - Публикация в Docker Hub под тегами `latest` и `<upstreamTag>`.
  - Подготовка артефактов: сохранение образов по платформам в `tar.gz` и публикация в GitHub Release.

---

## Требования

- Self‑hosted раннер(ы):
  - Для сборки: метка `self-hosted` (Linux, установлен Docker/QEMU/Buildx, доступ к сети Docker Hub).
  - Для оркестратора: метка `orchestrator` (выполняет диспатч и ожидание результатов).
- Доступ в Docker Hub:
  - Секреты репозитория: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (токен/патоль приложения).

---

## Ручной запуск workflow

Каждый сборочный workflow поддерживает `workflow_dispatch` с параметрами:

- build_amd64 / build_arm64 / build_386: выбрать целевые платформы.
- build_skip: пропустить стадию сборки (для отладки).
- build_force: принудительно собрать, даже если tag уже существует.
- release_skip: пропустить публикацию релиза/артефактов.

Запускать можно из вкладки Actions, выбрав нужный workflow:

- `Caddy-L4-Docker-selfhosted.yml`
- `WarpPlus-Docker-Selfhosted.yml`
- `3x-ui-Docker-selfhosted.yml`
- `usque-Docker-selfhosted.yml`

---

## Настройка

1) Форкните репозиторий (или используйте как есть).
2) Добавьте секреты в Settings → Secrets and variables → Actions:
   - `DOCKERHUB_USERNAME`
   - `DOCKERHUB_TOKEN`
3) Поднимите self‑hosted раннеры с нужными метками и доступом к Docker.
4) При необходимости измените целевые образы и апстримы в соответствующих workflow (переменные `DOCKER_REPO`, `REPO_EXT_NAME`, `REPO_EXT_URL` и т.д.).
5) При желании настройте расписание в `daily-trigger.yml`.

---

## Структура репозитория

- `.github/workflows/`
  - `daily-trigger.yml` — оркестратор ежедневных запусков, выполняет `workflow_dispatch` для сборочных сценариев и ждёт их завершения.
  - `Caddy-L4-Docker-selfhosted.yml` — сборка Caddy L4 из последнего релиза апстрима.
  - `WarpPlus-Docker-Selfhosted.yml` — сборка Warp Plus; дополнительно складывает бинарники в `bin/warp/` перед сборкой.
  - `3x-ui-Docker-selfhosted.yml` — сборка 3x-ui из апстрима.
  - `usque-Docker-selfhosted.yml` — сборка usque из апстрима.
- `bin/`
  - `caddy/` — кастомный `dockerfile` и `DockerEntrypoint.sh`.
  - `warp/` — `Dockerfile`, `DockerEntrypoint.sh`, шаблон `config.json.template`, вспомогательные скрипты и README по использованию.
  - `3x-ui/` — кастомный `dockerfile`, `DockerEntrypoint.sh`, `DockerInit.sh`.

Примечание: некоторые подкаталоги могут быть добавлены/изменены по мере необходимости в конкретных workflow.

---

## Использование образов

- Примеры docker-compose и переменные окружения для Warp Plus — в `bin/warp/ReadMe_RU.md`.
- Caddy L4 и 3x-ui используют стандартные параметры запуска; при необходимости ориентируйтесь на `Dockerfile` и `DockerEntrypoint.sh` в соответствующих `bin/*`.

---

## Типовой пайплайн (сокращённо)

1) Оркестратор запускает workflow проекта →
2) Workflow берёт последнюю версию из upstream Releases →
3) Проверяет, есть ли уже `<name>_<tag>` в тегах этого репо →
4) Скачивает/готовит исходники/бинарники (если нужно) →
5) Сборка образа (Buildx/QEMU) →
6) Push в Docker Hub (`latest` и `<tag>`) →
7) Сохранение per‑platform `tar.gz` → публикация в GitHub Release.

---

## Частые вопросы

- Почему сборка пропущена?
  - В репозитории уже есть tag вида `<name>_<upstreamTag>`, и не выставлен `build_force`.
- Где искать готовые образы?
  - В Docker Hub, namespace `torotin/*` (см. список выше).
- Можно ли изменить namespace/репозиторий?
  - Да, поменяйте `DOCKER_REPO` в соответствующем workflow.

---

## Благодарности

- Авторам и контрибьюторам проектов: `caddyserver/caddy`, `bepass-org/warp-plus`, `MHSanaei/3x-ui`, `Diniboy1123/usque`.
- Сообществу GitHub Actions и авторам action’ов: `docker/*`, `actions/*`, `actions/github-script`.

---

## Лицензия

Лицензия этого репозитория не задана явно. Использование сторонних проектов регулируется их собственными лицензиями в соответствующих апстрим‑репозиториях.

