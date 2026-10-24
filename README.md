# AutoDockerBuilder

Автоматическая сборка и публикация Docker-образов внешних проектов через GitHub Actions.

Репозиторий отслеживает последние upstream-релизы, собирает Docker images, публикует их в Docker Hub и создаёт GitHub Release с архивами образов.

> Под "release" в документе подразумевается GitHub Release вместе с соответствующим git tag.

---

## Что собирается

| Проект | Upstream | Docker Hub | Workflow | Image docs |
| --- | --- | --- | --- | --- |
| Caddy-L4 | [`caddyserver/caddy`](https://github.com/caddyserver/caddy) | `torotin/caddy-l4` | `Caddy-L4-Docker-selfhosted.yml` | [`bin/caddy/README.md`](bin/caddy/README.md) |
| 3x-ui | [`MHSanaei/3x-ui`](https://github.com/MHSanaei/3x-ui) | `torotin/3x-ui` | `3x-ui-Docker-selfhosted.yml` | [`bin/3x-ui/README.md`](bin/3x-ui/README.md) |
| usque | [`Diniboy1123/usque`](https://github.com/Diniboy1123/usque) | `torotin/usque` | `usque-Docker-selfhosted.yml` | [`bin/usque/README.md`](bin/usque/README.md) |
| telemt-stack | [`telemt/telemt`](https://github.com/telemt/telemt) + [`amirotin/telemt_panel`](https://github.com/amirotin/telemt_panel) | `torotin/telemt-stack` | `Telemt-Stack-Docker-selfhosted.yml` | [`bin/telemt-stack/README.md`](bin/telemt-stack/README.md) |
| Tor Proxy | Tor + [`lyrebird`](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird) + [`gost`](https://github.com/go-gost/gost) + [`dnsproxy`](https://github.com/AdguardTeam/dnsproxy) | `torotin/tor-proxy` | `TorProxy-Docker-selfhosted.yml` | [`bin/tor-proxy/README.md`](bin/tor-proxy/README.md) |

> Контракт каждого образа (порты, env, health, upstream docs) живёт в `bin/<project>/README.md`. Этот корневой README описывает общий pipeline сборки/релизов.
>
> Tor Proxy использует отдельный workflow: immutable tag собирается из stable-версий четырёх runtime-компонентов.

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
usque_v1.4.1
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
* `telemt-stack`

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

Для `Caddy-L4` и `telemt-stack` параметр `build_386` игнорируется, потому что `linux/386` не поддерживается.

---

## Платформы по проектам

| Проект    | Default platforms          | Supported platforms                          |
| --------- | -------------------------- | -------------------------------------------- |
| Caddy-L4     | `linux/amd64`              | `linux/amd64`, `linux/arm64/v8`              |
| 3x-ui        | `linux/amd64`, `linux/386` | `linux/amd64`, `linux/arm64/v8`, `linux/386` |
| usque        | `linux/amd64`, `linux/386` | `linux/amd64`, `linux/arm64/v8`, `linux/386` |
| telemt-stack | `linux/amd64`              | `linux/amd64`, `linux/arm64/v8`              |
| Tor Proxy    | `linux/amd64`              | `linux/amd64`                                |

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
docker pull torotin/usque:latest
docker pull torotin/usque:v1.4.1
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
usque-v1.4.1-linux-amd64.tar.gz
usque-latest.tar.gz
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
    _docker-project-build.yml          # общий reusable Docker pipeline
    daily-trigger.yml                  # оркестратор
    Caddy-L4-Docker-selfhosted.yml
    3x-ui-Docker-selfhosted.yml
    usque-Docker-selfhosted.yml
    Telemt-Stack-Docker-selfhosted.yml
    TorProxy-Docker-selfhosted.yml     # отдельный workflow для Tor Proxy

bin/
  caddy/          # см. bin/caddy/README.md
  3x-ui/          # см. bin/3x-ui/README.md
  usque/          # см. bin/usque/README.md
  telemt-stack/   # см. bin/telemt-stack/README.md
  tor-proxy/      # см. bin/tor-proxy/README.md
```

---

## Добавление нового проекта

Чтобы добавить новый проект на общий pipeline:

1. Создать каталог в `bin/<project>/`.
2. Добавить Dockerfile, необходимые scripts и **`bin/<project>/README.md`** (контракт образа: upstream, порты, env, health, consumers).
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
6. Добавить строку в таблицу «Что собирается» выше.

---

## Особенности отдельных проектов

Краткие отличия pipeline; полный контракт образа — в `bin/<project>/README.md`.

| Проект | Prepare | Pipeline notes |
| --- | --- | --- |
| [Caddy-L4](bin/caddy/README.md) | `in-repo-context` | amd64/arm64; `build_386` ignored |
| [3x-ui](bin/3x-ui/README.md) | `clone-release` → `WORKDIR/3x-ui` | `network: host`; build args `ALPINE_MIRROR`, `GOPROXY`, `GOSUMDB` |
| [usque](bin/usque/README.md) | `clone-release` → `WORKDIR/usque` | custom Dockerfile + entrypoint |
| [telemt-stack](bin/telemt-stack/README.md) | `in-repo-context` | combined telemt + telemt-panel binaries from GitHub Releases |
| [Tor Proxy](bin/tor-proxy/README.md) | dedicated workflow | amd64 only; composite immutable tag from Tor/lyrebird/gost/dnsproxy versions |

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

`daily-trigger.yml` реагирует на push в ветки `main`, `test`, `dev` и `prod`, и только если изменены файлы:

```yaml
branches: [main, test, dev, prod]
paths:
  - "bin/**"
  - "tests/tor-proxy/**"
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

Для отдельного `TorProxy-Docker-selfhosted.yml` этот input поддерживается и передается.

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
| `bin/telemt-stack/**` | `Telemt-Stack-Docker-selfhosted.yml` |
| `.github/workflows/Telemt-Stack-Docker-selfhosted.yml` | `Telemt-Stack-Docker-selfhosted.yml` |
| `bin/tor-proxy/**` | `TorProxy-Docker-selfhosted.yml` |
| `tests/tor-proxy/**` | `TorProxy-Docker-selfhosted.yml` |
| `.github/workflows/TorProxy-Docker-selfhosted.yml` | `TorProxy-Docker-selfhosted.yml` |
| `.github/workflows/_docker-project-build.yml` | все проекты на общем reusable workflow: `3x-ui`, `Caddy-L4`, `usque`, `telemt-stack` |

Примеры:

* изменение только `bin/caddy/dockerfile` запускает только Caddy-L4;
* изменение только `bin/3x-ui/DockerInit.sh` запускает только 3x-ui;
* изменение `_docker-project-build.yml` запускает `3x-ui`, `Caddy-L4`, `usque` и `telemt-stack`;
* изменение `daily-trigger.yml` само по себе не запускает проектные сборки, потому что этот файл не входит в project prefixes;
* изменение корневого `README.md` не запускает `daily-trigger.yml` (не в push `paths`);
* изменение только `bin/<project>/README.md` **запускает** соответствующий project workflow, потому что путь входит в prefix `bin/<project>/`.

Если ни один маршрут не совпал — workflow не запускается.

---

## Лицензия

Использование upstream-проектов регулируется их собственными лицензиями.
