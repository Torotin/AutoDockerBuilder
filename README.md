# AutoDockerBuilder

Автоматическая сборка и публикация Docker-образов внешних проектов через GitHub Actions.

Репозиторий отслеживает последние upstream-релизы, собирает Docker images, публикует их в Docker Hub и создаёт GitHub Release с архивами образов.

> Под "release" в документе подразумевается GitHub Release вместе с соответствующим git tag.

---

## Что собирается

| Проект | Upstream | Docker Hub | Workflow |
| --- | --- | --- | --- |
| Caddy-L4 | [`caddyserver/caddy`](https://github.com/caddyserver/caddy) | `torotin/caddy-l4` | `Caddy-L4-Docker-selfhosted.yml` |
| 3x-ui | [`MHSanaei/3x-ui`](https://github.com/MHSanaei/3x-ui) | `torotin/3x-ui` | `3x-ui-Docker-selfhosted.yml` |
| usque | [`Diniboy1123/usque`](https://github.com/Diniboy1123/usque) | `torotin/usque` | `usque-Docker-selfhosted.yml` |
| dockcheck | [`mag37/dockcheck`](https://github.com/mag37/dockcheck) | `torotin/dockcheck` | `dockcheck-Docker-selfhosted.yml` |
| telemt-stack | [`telemt/telemt`](https://github.com/telemt/telemt) + [`amirotin/telemt_panel`](https://github.com/amirotin/telemt_panel) | `torotin/telemt-stack` | `Telemt-Stack-Docker-selfhosted.yml` |
| Warp Plus | [`bepass-org/warp-plus`](https://github.com/bepass-org/warp-plus) | `torotin/warp-plus` | `WarpPlus-Docker-Selfhosted.yml` |
| Tor Proxy | [`torproject/tor`](https://gitlab.torproject.org/tpo/core/tor) + [`lyrebird`](https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird) + [`go-gost/gost`](https://github.com/go-gost/gost) + [`AdguardTeam/dnsproxy`](https://github.com/AdguardTeam/dnsproxy) | `torotin/tor-proxy` | `TorProxy-Docker-selfhosted.yml` |

> Важно: Warp Plus пока остаётся отдельным workflow и не переведён на общий `_docker-project-build.yml`.
> Warp Plus не использует общий `_docker-project-build.yml`,
> поэтому логика `build_force` и `recreate_release` может отличаться и реализована отдельно.
> Tor Proxy также использует отдельный workflow, поскольку его immutable tag составляется из stable-версий четырех runtime-компонентов.

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
| telemt-stack | `linux/amd64`           | `linux/amd64`, `linux/arm64/v8`              |
| Warp Plus | `linux/amd64`              | `linux/amd64`                                |
| Tor Proxy | `linux/amd64`              | `linux/amd64`                                |

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
    Telemt-Stack-Docker-selfhosted.yml # wrapper для telemt-stack
    WarpPlus-Docker-Selfhosted.yml   # отдельный workflow для Warp Plus
    TorProxy-Docker-selfhosted.yml   # отдельный workflow для Tor Proxy

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

  telemt-stack/
    dockerfile
    DockerEntrypoint.sh

  tor-proxy/
    Dockerfile
    entrypoint.sh
    bridge-sync.sh
    healthcheck.sh
    docker-compose.tor-proxy.yml

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

### telemt-stack

* build context: текущий репозиторий;
* `prepare_mode: in-repo-context`;
* публикует единый образ `torotin/telemt-stack`, объединяющий `telemt` и `telemt-panel`;
* скачивает бинарники из GitHub Releases [`telemt/telemt`](https://github.com/telemt/telemt) и [`amirotin/telemt_panel`](https://github.com/amirotin/telemt_panel);
* default platform: `linux/amd64`;
* supported platforms: `linux/amd64`, `linux/arm64/v8`;
* `linux/386` отключён.

### Warp Plus

Warp Plus пока использует отдельный workflow.

Особенности:

* собирается только `linux/amd64`;
* скачивает asset `warp-plus_linux-amd64.zip` из latest upstream release;
* извлекает бинарники `warp-plus` и `warp-scan`;
* собирает образ из `bin/warp`;
* публикует `latest` и `<upstream_tag>`;
* в GitHub Release прикладывается multi-arch/latest tarball.

### Tor Proxy

Tor Proxy использует отдельный workflow и публикует `torotin/tor-proxy` только для `linux/amd64`.
При сборке workflow разрешает текущие stable-версии Tor из `deb.torproject.org`,
Lyrebird из Tor Project GitLab, GOST и `dnsproxy` из GitHub Releases. Эти
версии явно передаются Dockerfile; его pinned defaults предназначены только
для ручной локальной сборки. Образ публикуется с `latest` и составным immutable
tag вида:

```text
tor-<tor-version>_lyrebird-<lyrebird-version>_gost-<gost-version>_dnsproxy-<dnsproxy-version>
```

`dnsproxy` собирается из exact Git tag разрешённой stable-версии: upstream
release не предоставляет отдельный checksum asset для Linux archive.

Контейнер предоставляет:

| Endpoint | Назначение |
| --- | --- |
| `tor-proxy:53` TCP/UDP | DNS через Tor внутри Docker network |
| `tor-proxy:1080` | SOCKS5 proxy |
| `tor-proxy:8080` | HTTP proxy |

Пример запуска находится в `bin/tor-proxy/docker-compose.tor-proxy.yml`.
Host-порты по умолчанию публикуются только на `127.0.0.1`, тогда как другие
контейнеры общей сети используют hostname `tor-proxy`:

```bash
curl --fail --silent --socks5-hostname tor-proxy:1080 \
  https://check.torproject.org/api/ip | grep '"IsTor":true'
```

Основные переменные окружения:

| Переменная | Default | Назначение |
| --- | --- | --- |
| `TOR_BRIDGES_ENABLED` | `true` | Включить мосты при запуске |
| `TOR_BRIDGE_TRANSPORT` | `auto` | `auto`, `obfs4`, `webtunnel` или `snowflake` |
| `TOR_BRIDGES_MAX_PER_TRANSPORT` | `2` | Максимум bridge lines одного transport; ограничивает CPU при bootstrap |
| `TOR_MAX_CLIENT_CIRCUITS_PENDING` | `4` | Ограничение одновременных ожидающих client circuits Tor |
| `TOR_IPV6_AVAILABLE` | `auto` | Разрешить IPv6 bridge endpoints только при рабочем outbound IPv6 VPS |
| `TOR_BRIDGES_OBFS4_URL` | Tor-Bridges-Collector raw feed | Источник `obfs4` |
| `TOR_BRIDGES_OBFS4_IPV6_URL` | Tor-Bridges-Collector raw feed | Источник IPv6 `obfs4`, используется только при исходящем IPv6 |
| `TOR_BRIDGES_WEBTUNNEL_URL` | Tor-Bridges-Collector raw feed | Источник `webtunnel` |
| `TOR_BRIDGES_SNOWFLAKE_URL` | official Tor Browser `pt_config.json` | Источник `snowflake` |
| `TOR_BOOTSTRAP_DNS_ENABLED` | `true` | Использовать внутренний encrypted DNS до/во время bootstrap |
| `TOR_BOOTSTRAP_DNS_UPSTREAMS` | AdGuard DoH, DoT, DoQ | Upstreams внутреннего `dnsproxy`; принимает также DNS stamps |
| `TOR_BOOTSTRAP_DNS_BOOTSTRAPS` | `94.140.14.14:53 94.140.15.15:53` | IPv4 bootstrap resolvers для encrypted upstream hostnames |
| `TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK` | `true` | Разрешить исходный container DNS как bootstrap fallback |
| `TOR_BOOTSTRAP_DNS_FALLBACKS` | пусто | Явная замена plaintext bootstrap fallback resolvers |
| `TOR_UPDATE_ON_START` | `true` | Попытаться обновить Tor из official APT repo перед запуском |
| `TOR_PROXY_LOGIN`, `TOR_PROXY_PASSWORD` | пусто | Опциональная auth для SOCKS5/HTTP; задаются только вместе |
| `TOR_PROXY_CPUS`, `TOR_PROXY_MEMORY_LIMIT` | `0.75`, `512m` | Compose resource limits для малого VPS |

Fetched bridges валидируются, дедуплицируются и сохраняются в
`/var/lib/tor-proxy`; при ошибке feed используется последний cache. В образ
включены official Tor Browser defaults для `obfs4` и `snowflake`; у
`webtunnel` bundled fallback нет, поэтому explicit `webtunnel` без рабочего
feed/cache завершает запуск ошибкой. Публичные feed
`scriptzteam/Tor-Bridges-Collector` являются недоверенным внешним источником и
могут быть заменены URL-переменными.

Для VPS с одним CPU `auto` сохраняет все три transport, но выбирает не более
двух мостов каждого типа и задаёт `MaxClientCircuitsPending 4`; это предотвращает
массовые параллельные попытки bootstrap. Внутренний `dnsproxy` обслуживает
только загрузку feeds и доменные соединения Lyrebird через DoH/DoT/DoQ;
upstreams опрашиваются параллельно, чтобы заблокированный DoT/DoQ не задерживал
доступный DoH.
Опубликованный порт `53` по-прежнему пересылает DNS исключительно через Tor.
При отказе encrypted upstreams plaintext fallback применяется только к этому
внутреннему bootstrap resolution.

Пример `.env` для малого VPS:

```dotenv
TOR_PROXY_CPUS=0.75
TOR_PROXY_MEMORY_LIMIT=512m
TOR_BRIDGES_MAX_PER_TRANSPORT=2
TOR_MAX_CLIENT_CIRCUITS_PENDING=4
TOR_IPV6_AVAILABLE=false
TOR_BOOTSTRAP_DNS_UPSTREAMS=https://dns.adguard-dns.com/dns-query tls://dns.adguard-dns.com quic://dns.adguard-dns.com
TOR_BOOTSTRAP_DNS_BOOTSTRAPS=94.140.14.14:53 94.140.15.15:53
TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK=true
```

Доступ к IPv6-only назначениям включен на SOCKS listener и зависит от
выбранного Tor exit с IPv6 и политики целевого ресурса. IPv6 bridge endpoints
не дают IPv6-over-IPv4 и фильтруются, если у VPS нет рабочего outbound IPv6.

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

Для `WarpPlus-Docker-Selfhosted.yml` `recreate_release` при push не передаётся, потому что Warp Plus использует отдельный workflow и не поддерживает этот input. Для отдельного `TorProxy-Docker-selfhosted.yml` этот input поддерживается и передается.

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
| `bin/telemt-stack/**` | `Telemt-Stack-Docker-selfhosted.yml` |
| `.github/workflows/Telemt-Stack-Docker-selfhosted.yml` | `Telemt-Stack-Docker-selfhosted.yml` |
| `bin/warp/**` | `WarpPlus-Docker-Selfhosted.yml` |
| `.github/workflows/WarpPlus-Docker-Selfhosted.yml` | `WarpPlus-Docker-Selfhosted.yml` |
| `bin/tor-proxy/**` | `TorProxy-Docker-selfhosted.yml` |
| `tests/tor-proxy/**` | `TorProxy-Docker-selfhosted.yml` |
| `.github/workflows/TorProxy-Docker-selfhosted.yml` | `TorProxy-Docker-selfhosted.yml` |
| `.github/workflows/_docker-project-build.yml` | все проекты на общем reusable workflow: `3x-ui`, `Caddy-L4`, `usque`, `dockcheck`, `telemt-stack` |

Примеры:

* изменение только `bin/caddy/dockerfile` запускает только Caddy-L4;
* изменение только `bin/3x-ui/DockerInit.sh` запускает только 3x-ui;
* изменение `_docker-project-build.yml` запускает `3x-ui`, `Caddy-L4`, `usque`, `dockcheck` и `telemt-stack`;
* изменение `daily-trigger.yml` само по себе не запускает проектные сборки, потому что этот файл не входит в project prefixes;
* изменение `README.md` не запускает `daily-trigger.yml`, потому что README не входит в push `paths`.

Если ни один маршрут не совпал — workflow не запускается.

---

## Лицензия

Использование upstream-проектов регулируется их собственными лицензиями.
