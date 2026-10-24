# 3x-ui (`torotin/3x-ui`)

Сборка панели [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) с кастомным Dockerfile (frontend → Go) и runtime entrypoint.

| | |
| --- | --- |
| Docker Hub | `torotin/3x-ui` |
| Upstream | [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) |
| Product docs | [docs.sanaei.dev](https://docs.sanaei.dev/docs/) |
| Workflow | `.github/workflows/3x-ui-Docker-selfhosted.yml` |
| Prepare mode | `clone-release` → `./WORKDIR/3x-ui` |
| Dockerfile / scripts | `bin/3x-ui/dockerfile`, `DockerEntrypoint.sh`, `DockerInit.sh`, `3x-ui_db_update.sh` |
| Platforms | default `linux/amd64`, `linux/386`; also `linux/arm64/v8` |

## Build notes

- Upstream latest GitHub Release tag drives image tag `torotin/3x-ui:<tag>` and `:latest`.
- Build uses `network: host` and build args `ALPINE_MIRROR`, `GOPROXY`, `GOSUMDB`.
- Frontend (Vite) is built before the Go binary so `internal/web/dist` is embedded.

## Runtime contract

Entrypoint responsibilities:

1. Optional `beforestart` scripts from `/mnt/sh/beforestart`
2. Copy extras from `/mnt/bin` → `/app/bin`
3. Start `x-ui`, then `afterstart` scripts from `/mnt/sh/afterstart`
4. Optional Fail2Ban jail when `XUI_ENABLE_FAIL2BAN=true`

Mount expectations are **consumer-defined** (panel DB, env, script hooks). This image does not ship a full compose stack.

### Notable environment variables

| Variable | Purpose |
| --- | --- |
| `XUI_ENABLE_FAIL2BAN` | enable Fail2Ban helper (`true`/`false`) |
| `XUI_LOG_FOLDER` | log dir for Fail2Ban jail (default `/var/log/x-ui`) |

Panel product settings (webBasePath, subscription ports, API) follow upstream docs and the deploying compose/env — not duplicated here.

## Local build sketch

Workflow clones upstream into `WORKDIR/3x-ui` and overlays custom Dockerfile/scripts. For local iteration, prefer the project workflow or mirror that prepare step; do not assume `docker build` from this folder alone without upstream sources.

## Consumers

Primary consumer: `Torotin/3x-ui_pro_Docker` (`docker-proxy/compose.d/12-3x-ui.yml` + `docker-proxy/3x-ui/`). Traefik routes, managed Xray desired state, and panel API automation live in that repository.
