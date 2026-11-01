# prizrak-core (`torotin/prizrak-core`)

Container image for [legiz-ru/Prizrak-Core](https://github.com/legiz-ru/Prizrak-Core): bakes a pinned release binary plus geo rules, then polls for newer upstream releases while the container runs.

| | |
| --- | --- |
| Docker Hub | `torotin/prizrak-core` |
| Upstream | [legiz-ru/Prizrak-Core](https://github.com/legiz-ru/Prizrak-Core) |
| Workflow | `.github/workflows/Prizrak-Core-Docker-selfhosted.yml` (Task 5) |
| Prepare mode | `in-repo-context`, build context repo root (`.`) |
| Dockerfile / scripts | `bin/prizrak-core/Dockerfile`, `DockerEntrypoint.sh`, `update-core.sh` |
| Example compose | `bin/prizrak-core/docker-compose.prizrak-core.yml` |
| Platforms | `linux/amd64`, `linux/arm64/v8` |

## Build-time arguments

| Build arg | Default | Purpose |
| --- | --- | --- |
| `PRIZRAK_REPO` | `legiz-ru/Prizrak-Core` | GitHub repo for release downloads |
| `PRIZRAK_VERSION` | *(required)* | Release tag baked into the image (CI: `repo_tag_build_arg`) |
| `PRIZRAK_CORE_VARIANT` | `v3` | amd64 asset variant (`v1` / `v2` / `v3`; ignored on arm64) |
| `TARGETARCH` | from Buildx | `amd64` or `arm64` — selects the release asset name |

CI copies `DockerEntrypoint.sh` and `update-core.sh` to the repo root before `docker build`; the Dockerfile `COPY`s them from there together with `bin/prizrak-core/asset-name.sh`.

Local smoke build from repo root:

```bash
cp bin/prizrak-core/DockerEntrypoint.sh DockerEntrypoint.sh
cp bin/prizrak-core/update-core.sh update-core.sh
docker build -f bin/prizrak-core/Dockerfile \
  --build-arg PRIZRAK_VERSION=v1.19.33-r8 \
  --build-arg PRIZRAK_CORE_VARIANT=v3 \
  -t prizrak-core:local .
```

At build time the core is downloaded from **Prizrak-Core GitHub releases** (via `asset-name.sh`). Geo (`geoip.dat`, `geosite.dat`, `geoip.metadb`) is fetched from [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) `releases/latest`.

## Runtime layout

| Path | Role |
| --- | --- |
| `/opt/prizrak/prizrak-core` | Writable installed binary |
| `/opt/prizrak/installed-release` | Tag last successfully installed by bake or updater |
| `/root/.config/mihomo/` | Config volume (`config.yaml`, geo, runtime overrides) |
| `/temp/prizrak-update/` | Staging area during updates (not persisted) |
| `/temp/prizrak-backup/` | Backup binary + geo before replace |
| `/temp/prizrak-core.pid` | Child PID for hard restart |

`VOLUME ["/root/.config/mihomo/"]` — bind-mount or named volume so `config.yaml` and geo survive restarts.

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `PRIZRAK_BIN` | `/opt/prizrak/prizrak-core` | Core binary path |
| `PRIZRAK_CONFIG_DIR` | `/root/.config/mihomo` | Mihomo/Prizrak config directory (`-d`) |
| `PRIZRAK_STATE_FILE` | `/opt/prizrak/installed-release` | Installed release tag |
| `PRIZRAK_UPDATE_INTERVAL` | `1h` | Poll interval (`Nh`, `Nm`, `Ns`, or seconds) |
| `PRIZRAK_CORE_VARIANT` | `v3` | amd64 variant for **runtime** release downloads |
| `PRIZRAK_REPO` | `legiz-ru/Prizrak-Core` | Upstream GitHub repo |
| `PRIZRAK_CONTROLLER_URL` | *(from config)* | External controller base URL for soft restart |
| `PRIZRAK_SECRET` | *(from config)* | Bearer token for controller `/restart` |
| `PRIZRAK_UPDATE_SCRIPT` | `/opt/prizrak/update-core.sh` | Updater script path |
| `PRIZRAK_PID_FILE` | `/temp/prizrak-core.pid` | Core child PID file |
| `PRIZRAK_GEO_BASE_URL` | `https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest` | Base URL for runtime geo downloads (`geoip.dat`, `geosite.dat`, `geoip.metadb`) |

Entrypoint passthrough arguments are forwarded to the core (for example `-v` for version).

## Update semantics

On each interval, `update-core.sh`:

1. Acquires a lock (skip tick if another update runs).
2. Resolves the latest tag from the GitHub Releases API and compares it to `installed-release`.
3. **Stages** the new core (from Prizrak-Core releases) and geo (from [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat), same source as bake; override with `PRIZRAK_GEO_BASE_URL`) under `/temp/prizrak-update/` — if download or unpack fails, nothing on disk is changed.
4. **Backs up** the current binary and geo under `/temp/prizrak-backup/`.
5. Replaces the binary and geo, then **soft-restarts** via `POST …/restart` when controller URL/secret are available (`PRIZRAK_CONTROLLER_URL` / `PRIZRAK_SECRET` override `config.yaml`).
6. Runs `PRIZRAK_HEALTH_CMD` (default success); on failure **restores** backup and restarts again without advancing `installed-release`.
7. On success, writes the new tag to `installed-release` and removes the stage dir.

Stock Mihomo **`/upgrade` is not used** as a download channel for the core; binaries come only from Prizrak-Core release assets (wget/curl), matching the upstream design constraint.

## Example

```bash
mkdir -p ./prizrak-config
# place config.yaml in ./prizrak-config/
docker compose -f bin/prizrak-core/docker-compose.prizrak-core.yml up -d
```

```bash
docker run --rm -v "$(pwd)/prizrak-config:/root/.config/mihomo" torotin/prizrak-core:latest -v
```
