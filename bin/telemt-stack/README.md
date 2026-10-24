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

## Runtime contract

Entrypoint starts:

1. `telemt /etc/telemt/config.toml`
2. Optionally `telemt-panel --config /etc/telemt-panel/config.toml` when `TELEMT_PANEL_ENABLED` is truthy

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
