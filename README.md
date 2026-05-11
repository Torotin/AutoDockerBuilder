# AutoDockerBuilder

Автоматическая сборка и публикация Docker-образов внешних проектов через GitHub Actions.

Репозиторий отслеживает последние upstream-релизы, собирает Docker images, публикует их в Docker Hub и создаёт GitHub Release с архивами образов.

> Под "release" в документе подразумевается GitHub Release вместе с соответствующим git tag.

---

## Что собирается

| Проект | Upstream | Docker Hub | Workflow |
| --- | --- | --- | --- |
| Caddy-L4 | `caddyserver/caddy` | `torotin/caddy-l4` | `Caddy-L4-Docker-selfhosted.yml` |
| 3x-ui | `MHSanaei/3x-ui` | `torotin/3x-ui` | `3x-ui-Docker-selfhosted.yml` |
| usque | `Diniboy1123/usque` | `torotin/usque` | `usque-Docker-selfhosted.yml` |
| dockcheck | `mag37/dockcheck` | `torotin/dockcheck` | `dockcheck-Docker-selfhosted.yml` |
| Warp Plus | `bepass-org/warp-plus` | `torotin/warp-plus` | `WarpPlus-Docker-Selfhosted.yml` |

> Важно: Warp Plus пока остаётся отдельным workflow и не переведён на общий `_docker-project-build.yml`.
> Warp Plus не использует общий `_docker-project-build.yml`,
> поэтому логика `build_force` и `recreate_release` может отличаться и реализована отдельно.

---

## Архитектура workflow

### 1. Оркестратор

Файл:

```text
.github/workflows/daily-trigger.yml
```

Запускается:

* по расписанию: каждый день в `03:00 UTC`;
* вручную через `workflow_dispatch`;
* при push в ветки `main` или `test`, если изменены файлы в `bin/**` или `.github/workflows/**`.

Оркестратор последовательно запускает проектные workflow и ждёт завершения каждого.

При push он запускает только те workflow, чьи файлы были затронуты. Например:

* изменение `bin/caddy/**` запускает Caddy-L4;
* изменение `bin/3x-ui/**` запускает 3x-ui;
* изменение общего `_docker-project-build.yml` запускает проекты, которые от него зависят.

---

### 2. Общий reusable workflow

Файл:

```text
.github/workflows/_docker-project-build.yml
```

Содержит три основные стадии:

1. `prepare`
2. `build`
3. `release`

#### `prepare`

* checkout текущего репозитория;
* установка `jq`, `curl`, `git`, `tree`;
* получение latest release tag из upstream GitHub Releases;
* формирование release tag в формате:

```text
<release_tag_prefix>_<upstream_tag>
```

Примеры:

```text
Caddy-L4_v2.10.0
3x-ui_v2.5.10
dockcheck_v0.7.8
```

* проверка существующего GitHub Release;
* пропуск сборки, если release уже существует и не включён `build_force`
  (не применяется при push, так как build_force устанавливается автоматически)

#### `build`

* выбор платформ;
* подготовка build context;
* подстановка кастомного Dockerfile / entrypoint / init script;
* подготовка Docker build args;
* включение QEMU, если нужны `arm64` или `386`;
* сборка через Docker Buildx;
* push в Docker Hub с тегами:

```text
<docker_repo>:latest
<docker_repo>:<upstream_tag>
```

Используется комбинированный BuildKit cache:

```text
cache-from:
  type=gha,scope=<artifact_prefix>
  type=registry,ref=<docker_repo>:buildcache

cache-to:
  type=gha,mode=max,scope=<artifact_prefix>
  type=registry,ref=<docker_repo>:buildcache,mode=max
```

`type=gha` ускоряет повторные сборки внутри GitHub Actions.

`type=registry` сохраняет BuildKit cache в Docker Hub как служебный tag `<docker_repo>:buildcache`.

`scope=<artifact_prefix>` нужен, чтобы разные проекты не перетирали общий GitHub Actions cache друг друга.

#### `release`

* pull опубликованных образов;
* экспорт per-platform архивов в `tar.gz`;
* экспорт `latest` архива;
* генерация release body со ссылками на upstream repository, upstream release и workflow run;
* создание GitHub Release (если не включён `release_skip`);
* прикрепление архивов к релизу;
* удаление старых workflow runs.

---

## Поддерживаемые режимы подготовки build context

Общий workflow поддерживает два режима.

### `clone-release`

Используется для проектов, где нужно клонировать upstream-репозиторий и собрать образ из его release tag.

Требует:

```yaml
repo_ext_url: https://github.com/<owner>/<repo>.git
repo_ext_name: <owner>/<repo>
prepare_mode: clone-release
workdir: ./WORKDIR/<project>
```

Применяется для:

* `3x-ui`
* `usque`
* `dockcheck`

Каждый `clone-release` проект должен использовать отдельный подкаталог
`./WORKDIR/<project>`, чтобы Docker Build summary и временный build context не
смешивали разные upstream-проекты.

### `in-repo-context`

Используется, когда build context находится в текущем репозитории.

Требует:

```yaml
prepare_mode: in-repo-context
workdir: .
```

Применяется для:

* `Caddy-L4`

---

## Ручной запуск

> Важно: при запуске через API (`workflow_dispatch`) значения boolean-параметров передаются как строки (`'true'` / `'false'`).

Каждый проектный workflow можно запустить вручную во вкладке **Actions**.

Общие параметры:

| Параметр | Назначение |
| --- | --- |
| `build_amd64` | собрать `linux/amd64` |
| `build_arm64` | собрать `linux/arm64/v8` |
| `build_386` | собрать `linux/386`, если проект поддерживает |
| `build_skip` | пропустить сборку |
| `build_force` | собрать даже при существующем GitHub Release |
| `recreate_release` | удалить существующий GitHub Release перед созданием нового |
| `release_skip` | не создавать GitHub Release |

Для `dockcheck` доступны только `amd64` и `arm64`.

Для `Caddy-L4` параметр `build_386` игнорируется, потому что `linux/386` не поддерживается.

---

## Платформы по проектам

| Проект    | Default platforms          | Supported platforms                          |
| --------- | -------------------------- | -------------------------------------------- |
| Caddy-L4  | `linux/amd64`              | `linux/amd64`, `linux/arm64/v8`              |
| 3x-ui     | `linux/amd64`, `linux/386` | `linux/amd64`, `linux/arm64/v8`, `linux/386` |
| usque     | `linux/amd64`, `linux/386` | `linux/amd64`, `linux/arm64/v8`, `linux/386` |
| dockcheck | `linux/amd64`              | `linux/amd64`, `linux/arm64/v8`              |
| Warp Plus | `linux/amd64`              | `linux/amd64`                                |

---

## Docker Hub теги

После успешной сборки публикуются:

```text
<docker_repo>:latest
<docker_repo>:<upstream_tag>
```

Для BuildKit cache также публикуется служебный tag:

```text
<docker_repo>:buildcache
```

Этот tag не предназначен для запуска контейнера. Он используется Docker Buildx как registry cache.

Пример:

```bash
docker pull torotin/dockcheck:latest
docker pull torotin/dockcheck:v0.7.8
```

---

## GitHub Releases

Для каждого собранного upstream-релиза создаётся GitHub Release.

Формат tag:

```text
<release_tag_prefix>_<upstream_tag>
```

Формат title:

```text
<release_name_prefix> Release <upstream_tag>
```

Release body содержит:

```text
Автоматическая Docker-сборка `<project_name>` из upstream release `<upstream_tag>`.

### Sources
- Upstream repository: https://github.com/<upstream_owner>/<upstream_repo>
- Upstream release: https://github.com/<upstream_owner>/<upstream_repo>/releases/tag/<upstream_tag>
- Build workflow: https://github.com/<owner>/<repo>/actions/runs/<run_id>

### Images
`<docker_repo>:<upstream_tag>`
`<docker_repo>:latest`

### Platforms
- `<platform>`
```

К релизу прикладываются архивы:

```text
<artifact_prefix>-<upstream_tag>-<platform>.tar.gz
<artifact_prefix>-latest.tar.gz
```

Пример:

```text
dockcheck-v0.7.8-linux-amd64.tar.gz
dockcheck-latest.tar.gz
```

---

## Секреты

В настройках репозитория должны быть заданы:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
```

Они используются для Docker Hub login и push образов.

---

## Permissions

Проектные workflow используют:

```yaml
permissions:
  contents: write
  actions: write
```

`contents: write` нужен для создания GitHub Releases.

`actions: write` нужен для работы с workflow runs и cleanup.

Warp Plus дополнительно использует:

```yaml
packages: write
```

---

## Self-hosted runner

После рефакторинга основные reusable workflow jobs выполняются на:

```text
ubuntu-latest
```

Оркестратор `daily-trigger.yml` выполняется на runner с label:

```text
orchestrator
```

Для локальной проверки workflow через `actionlint` кастомный label описан в `.github/actionlint.yaml`:

```yaml
self-hosted-runner:
  labels:
    - orchestrator
```

---

## Структура репозитория

```text
.github/
  workflows/
    _docker-project-build.yml        # общий reusable Docker pipeline
    daily-trigger.yml                # оркестратор
    Caddy-L4-Docker-selfhosted.yml   # wrapper для Caddy-L4
    3x-ui-Docker-selfhosted.yml      # wrapper для 3x-ui
    usque-Docker-selfhosted.yml      # wrapper для usque
    dockcheck-Docker-selfhosted.yml  # wrapper для dockcheck
    WarpPlus-Docker-Selfhosted.yml   # отдельный workflow для Warp Plus

bin/
  caddy/
    dockerfile
    DockerEntrypoint.sh

  3x-ui/
    dockerfile
    DockerEntrypoint.sh
    DockerInit.sh

  usque/
    Dockerfile
    DockerEntrypoint.sh
    DockerInit.sh

  dockcheck/
    Dockerfile
    entrypoint.sh
    docker-compose.dockcheck.yml
    .env.template

  warp/
    Dockerfile
    DockerEntrypoint.sh
    config.json.template
    ...
```

---

## Добавление нового проекта

Чтобы добавить новый проект на общий pipeline:

1. Создать каталог в `bin/<project>/`.
2. Добавить Dockerfile и необходимые scripts.
3. Создать новый workflow в `.github/workflows/`.
4. Вызвать reusable workflow:

```yaml
jobs:
  docker:
    uses: ./.github/workflows/_docker-project-build.yml
    with:
      project_name: example
      release_tag_prefix: example
      release_name_prefix: example
      artifact_prefix: example
      repo_ext_url: https://github.com/example/example.git
      repo_ext_name: example/example
      docker_repo: torotin/example
      prepare_mode: clone-release
      workdir: ./WORKDIR/example
      custom_dockerfile: ./bin/example/Dockerfile
      custom_entrypoint: ./bin/example/entrypoint.sh
      default_platforms: linux/amd64
      supported_platforms: linux/amd64,linux/arm64/v8
      build_amd64: ${{ inputs.build_amd64 }}
      build_arm64: ${{ inputs.build_arm64 }}
      build_386: false
      build_skip: ${{ inputs.build_skip }}
      build_force: ${{ inputs.build_force }}
      recreate_release: ${{ inputs.recreate_release }}
      release_skip: ${{ inputs.release_skip }}
    secrets: inherit
```

5. Добавить маршрут в `daily-trigger.yml`.

---

## Особенности отдельных проектов

### Caddy-L4

* build context: текущий репозиторий;
* `prepare_mode: in-repo-context`;
* поддерживает только `linux/amd64` и `linux/arm64/v8`;
* `linux/386` отключён.

### 3x-ui

* upstream клонируется по latest release tag;
* build context: `./WORKDIR/3x-ui`;
* используется custom Dockerfile, entrypoint и init script;
* default platforms: `linux/amd64`, `linux/386`;
* build выполняется с `network: host`;
* передаются build args:

```text
ALPINE_MIRROR
GOPROXY
GOSUMDB
```

### usque

* upstream клонируется по latest release tag;
* build context: `./WORKDIR/usque`;
* используется custom Dockerfile, entrypoint и init script;
* default platforms: `linux/amd64`, `linux/386`.

### dockcheck

* upstream клонируется по latest release tag;
* build context: `./WORKDIR/dockcheck`;
* поддерживает `linux/amd64` и `linux/arm64/v8`;
* `linux/386` принудительно отключён;
* upstream tag передаётся в Docker build arg:

```text
DOCKCHECK_REF
```

### Warp Plus

Warp Plus пока использует отдельный workflow.

Особенности:

* собирается только `linux/amd64`;
* скачивает asset `warp-plus_linux-amd64.zip` из latest upstream release;
* извлекает бинарники `warp-plus` и `warp-scan`;
* собирает образ из `bin/warp`;
* публикует `latest` и `<upstream_tag>`;
* в GitHub Release прикладывается multi-arch/latest tarball.

---

## Типовой pipeline

```text
daily-trigger.yml
  ↓
project workflow
  ↓
_docker-project-build.yml
  ↓
prepare
  ↓
build & push Docker image
  ↓
export tar.gz archives
  ↓
create GitHub Release
```

---

## Поведение при запуске

### При push

`daily-trigger.yml` реагирует на push только в ветки `main` и `test`, и только если изменены файлы:

```yaml
branches: [main, test]
paths:
  - "bin/**"
  - ".github/workflows/**"
```

После запуска оркестратор не запускает все сборки подряд. Он сначала собирает список изменённых файлов:

* из `context.payload.commits`;
* если payload не содержит файлов, через GitHub API compare между `before` и текущим `sha`.

Затем каждый путь нормализуется:

* удаляется начальный `./`;
* Windows-разделители `\` заменяются на `/`.

После этого изменённые файлы сравниваются с project registry внутри `daily-trigger.yml`.

Каждый проект в registry содержит:

```js
{
  workflow: '3x-ui-Docker-selfhosted.yml',
  prefixes: [
    'bin/3x-ui/',
    '.github/workflows/3x-ui-Docker-selfhosted.yml',
    '.github/workflows/_docker-project-build.yml',
  ],
  inputs: {},
  recreateReleaseOnPush: true,
}
```

Если хотя бы один изменённый файл начинается с одного из `prefixes`, соответствующий workflow попадает в очередь запуска.

Для каждого выбранного workflow при push автоматически передаются inputs:

```text
build_force = true
```

Для проектов на общем `_docker-project-build.yml` дополнительно передаётся:

```text
recreate_release = true
```

Это означает:

* сборка выполняется всегда, даже если GitHub Release уже существует;
* перед созданием нового release старый GitHub Release удаляется;
* вместе с release удаляется соответствующий git tag;
* затем создаётся новый release с тем же именем tag, но с актуальными artefacts и release body.

Для `WarpPlus-Docker-Selfhosted.yml` `recreate_release` при push не передаётся, потому что Warp Plus использует отдельный workflow и не поддерживает этот input.

Выбранные workflow запускаются последовательно:

1. оркестратор делает snapshot текущих `workflow_dispatch` runs для проекта;
2. вызывает `createWorkflowDispatch`;
3. ждёт появления нового run до `5 минут`;
4. ждёт завершения run до `6 часов`;
5. если run завершился не `success`, оркестратор помечает себя failed и останавливает очередь;
6. если run не удалось обнаружить или ожидание завершения сорвалось по timeout/API warning, оркестратор пишет warning и переходит к следующему проекту.

Между проектами есть пауза `1 секунда`.

### При schedule / manual

* поведение стандартное;
* сборка пропускается, если release уже существует и не включён `build_force`;
* можно управлять через параметры:

```text
build_force
recreate_release
build_skip
release_skip
```

* если включён `release_skip`, этап создания GitHub Release пропускается;

---

## Логика выбора проектов при push

Оркестратор анализирует список изменённых файлов и запускает только соответствующие workflow.

Текущие маршруты:

| Изменённый путь | Запускаемый workflow |
| --- | --- |
| `bin/3x-ui/**` | `3x-ui-Docker-selfhosted.yml` |
| `.github/workflows/3x-ui-Docker-selfhosted.yml` | `3x-ui-Docker-selfhosted.yml` |
| `bin/caddy/**` | `Caddy-L4-Docker-selfhosted.yml` |
| `.github/workflows/Caddy-L4-Docker-selfhosted.yml` | `Caddy-L4-Docker-selfhosted.yml` |
| `bin/usque/**` | `usque-Docker-selfhosted.yml` |
| `.github/workflows/usque-Docker-selfhosted.yml` | `usque-Docker-selfhosted.yml` |
| `bin/dockcheck/**` | `dockcheck-Docker-selfhosted.yml` |
| `.github/workflows/dockcheck-Docker-selfhosted.yml` | `dockcheck-Docker-selfhosted.yml` |
| `bin/warp/**` | `WarpPlus-Docker-Selfhosted.yml` |
| `.github/workflows/WarpPlus-Docker-Selfhosted.yml` | `WarpPlus-Docker-Selfhosted.yml` |
| `.github/workflows/_docker-project-build.yml` | все проекты на общем reusable workflow: `3x-ui`, `Caddy-L4`, `usque`, `dockcheck` |

Примеры:

* изменение только `bin/caddy/dockerfile` запускает только Caddy-L4;
* изменение только `bin/3x-ui/DockerInit.sh` запускает только 3x-ui;
* изменение `_docker-project-build.yml` запускает `3x-ui`, `Caddy-L4`, `usque` и `dockcheck`;
* изменение `daily-trigger.yml` само по себе не запускает проектные сборки, потому что этот файл не входит в project prefixes;
* изменение `README.md` не запускает `daily-trigger.yml`, потому что README не входит в push `paths`.

Если ни один маршрут не совпал — workflow не запускается.

---

## Лицензия

Использование upstream-проектов регулируется их собственными лицензиями.
