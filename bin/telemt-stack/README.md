# telemt-stack (`torotin/telemt-stack`)

Единый образ: [telemt](https://github.com/telemt/telemt) + [telemt-panel](https://github.com/amirotin/telemt_panel). Имя `telemt-stack` специально отличается от upstream `ghcr.io/telemt/telemt`.

| | |
| --- | --- |
| Docker Hub | `torotin/telemt-stack` |
| Upstream binaries | [telemt/telemt](https://github.com/telemt/telemt) + [amirotin/telemt_panel](https://github.com/amirotin/telemt_panel) |
| Telemt docs | [telemt/docs](https://github.com/telemt/telemt/tree/main/docs) |
| Workflow | `.github/workflows/Telemt-Stack-Docker-selfhosted.yml` |
| Prepare mode | `in-repo-context` |
| Files | `dockerfile`, `DockerEntrypoint.sh`, `docker-compose.telemt-stack.yml`, `telemt-config.toml`, `telemt-panel-config.toml` |
| Platforms | default `linux/amd64`; also `linux/arm64/v8` (`linux/386` off) |

## Version selection

| Component | Source | Rule |
| --- | --- | --- |
| `telemt` | [telemt/telemt](https://github.com/telemt/telemt) | latest **stable** GitHub Release (`/releases/latest`) |
| `telemt-panel` | [amirotin/telemt_panel](https://github.com/amirotin/telemt_panel) | newest non-draft release, **including prereleases** |

CI writes a composite Docker/GitHub tag:

```text
torotin/telemt-stack:<telemtTag>_panel-<panelTag>
```

Example: `torotin/telemt-stack:v3.5.15_panel-v1.0.0-rc.3`.

Dockerfile build-args still accept explicit tags. For local builds, `TELEMT_PANEL_VERSION=latest` resolves the newest panel release including prereleases; use `latest-stable` to force `/releases/latest` for the panel.

Resolved tags are also written into the image as `/usr/local/share/telemt-version` and `/usr/local/share/telemt-panel-version`.

## GeoIP (telemt-panel)

Build downloads MaxMind GeoLite2 `.mmdb` files from [P3TERX/GeoLite.mmdb](https://github.com/P3TERX/GeoLite.mmdb) (direct HTTPS `.mmdb`, not archives). No MaxMind license key is used.

| Path | Role |
| --- | --- |
| `/usr/share/telemt-panel/geoip/GeoLite2-City.mmdb` | City DB (image, world-readable) |
| `/usr/share/telemt-panel/geoip/GeoLite2-ASN.mmdb` | ASN DB |
| `/usr/share/telemt-panel/geoip/GeoLite2-Country.mmdb` | Country DB |
| `/usr/share/telemt-panel/geoip/SOURCE.txt` | Mirror URL + UTC fetch stamp + byte sizes |
| `/var/lib/telemt-panel/geoip/*` | Optional seed copy at container start (missing files only) |

Point panel `[geoip]` absolute paths at the image files (see `telemt-panel-config.toml`) or at the seeded `data_dir` copies. This does not replace URL-based / `ensure-geoip.sh` flows: if files already exist under the data dir, the entrypoint leaves them alone.

| Variable | Default | Purpose |
| --- | --- | --- |
| `TELEMT_GEOIP_IMAGE_DIR` | `/usr/share/telemt-panel/geoip` | baked MMDB directory |
| `TELEMT_GEOIP_DATA_DIR` | `/var/lib/telemt-panel/geoip` | seed destination for volume/`data_dir` layouts |
| `TELEMT_GEOIP_SEED` | `true` | copy missing MMDB/SOURCE into data dir on start |

Local check after build:

```bash
docker run --rm --entrypoint ls torotin/telemt-stack:latest -la /usr/share/telemt-panel/geoip
docker run --rm --entrypoint sh torotin/telemt-stack:latest -c \
  'grep -a -q $'\''\xab\xcd\xefMaxMind.com'\'' /usr/share/telemt-panel/geoip/GeoLite2-City.mmdb && cat /usr/share/telemt-panel/geoip/SOURCE.txt'
```

## Runtime contract

Entrypoint starts:

1. Seed missing GeoIP files into `TELEMT_GEOIP_DATA_DIR` (when enabled)
2. `telemt /etc/telemt/config.toml`
3. Optionally `telemt-panel --config /etc/telemt-panel/config.toml` when `TELEMT_PANEL_ENABLED` is truthy

| Variable | Default | Purpose |
| --- | --- | --- |
| `TELEMT_PANEL_ENABLED` | `true` | run bundled panel; set `false` for external panel only |

### Typical ports (see compose sample)

| Port | Role |
| --- | --- |
| `9443` | MTProto / Fake TLS listener (config-dependent) |
| `8080` | telemt-panel UI |
| `9091` | telemt API (sample binds `127.0.0.1` on host) |
| `9090` | metrics (sample binds `127.0.0.1` on host) |

Control bind addresses for published host ports: `TELEMT_API_BIND_ADDRESS`, `TELEMT_METRICS_BIND_ADDRESS`.

### Config templates

```text
bin/telemt-stack/telemt-config.toml
bin/telemt-stack/telemt-panel-config.toml
```

Replace placeholders (API token, MTProxy secret, password hash, JWT) before use.

Panel Logs UI may require Docker socket + `container_name = "telemt-stack"` in panel config. Socket access is powerful — only on trusted hosts, or omit the mount if UI logs are not needed.

## Example

```bash
docker compose -f bin/telemt-stack/docker-compose.telemt-stack.yml up -d
```

## Consumers

Primary consumer: `Torotin/3x-ui_pro_Docker` (`docker-proxy/compose.d/15-telemt.yml`, optional via `ENABLE_TELEMT`). Stack Traefik path for the panel and network pins live there.
