# Caddy-L4 (`torotin/caddy-l4`)

Кастомный Caddy с Layer 4 и набором xcaddy-плагинов. Сборка: `in-repo-context` из `bin/caddy/`.

| | |
| --- | --- |
| Docker Hub | `torotin/caddy-l4` |
| Upstream version source | [caddyserver/caddy](https://github.com/caddyserver/caddy) (release tag → image tag) |
| Workflow | `.github/workflows/Caddy-L4-Docker-selfhosted.yml` |
| Dockerfile | `bin/caddy/dockerfile` |
| Entrypoint | `bin/caddy/DockerEntrypoint.sh` |
| Platforms | `linux/amd64`, `linux/arm64/v8` (`linux/386` отключён) |

## Upstream docs

- [Caddy documentation](https://caddyserver.com/docs/)
- [mholt/caddy-l4](https://github.com/mholt/caddy-l4) · [docs/](https://github.com/mholt/caddy-l4/tree/master/docs)
- CrowdSec Caddy bouncer: [hslatman/caddy-crowdsec-bouncer](https://github.com/hslatman/caddy-crowdsec-bouncer)

## Modules built into the image

Сборка через `xcaddy` (см. `dockerfile`):

- `github.com/mholt/caddy-l4`
- `github.com/hslatman/caddy-crowdsec-bouncer` (`http`, `layer4`, `appsec`)
- `github.com/mholt/caddy-ratelimit`
- `github.com/caddyserver/forwardproxy` → `klzgrad/forwardproxy@naive`
- `github.com/greenpau/caddy-security`
- `github.com/KimMachineGun/automemlimit`, `pkg.jsn.cam/caddy-defender`
- `abiosoft/caddy-json-schema`, `caddy-inspect`, `caddy-exec`
- `caddyserver/transform-encoder`, `cache-handler`

Наличие L4 в образе **не означает**, что потребительский стек обязан публиковать L4 entrypoints.

## Ports (image defaults)

| Port | Notes |
| --- | --- |
| `80` / `443` / `443/udp` | HTTP/HTTPS / HTTP3 |
| `2019` | Caddy admin |
| `9000` / `9000/udp` | reserved for L4 examples |

## Runtime contract

- Config: Caddyfile or JSON (`USE_JSON`); TLS data under XDG paths (`/config`, `/data`).
- Entrypoint: config live-reload, optional defender CIDR snippet refresh, optional PEM sync helpers, optional upstream healthcheck loop.
- `auto_https` and public TLS policy are **consumer-owned** (many stacks terminate TLS at Traefik and run Caddy internal-only).

### Useful environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `USE_JSON` | `false` | JSON config instead of Caddyfile |
| `CLEAR_START` | `false` | start Caddy only (no watchers) |
| `HEALTHCHECK_ENABLED` | `false` | enable entrypoint healthcheck loop |
| `LOGLEVEL` | `INFO` | entrypoint log level |
| `LAPI_URL` | `http://127.0.0.1:8080/v1` | CrowdSec LAPI base for bouncer snippets |
| `CERT_DIR` | ACME certs path under `/data/caddy/...` | PEM sync root |
| `GOMEMLIMIT` | `512MiB` | Go memory soft limit |

## Local build sketch

```bash
docker build -f bin/caddy/dockerfile -t torotin/caddy-l4:local bin/caddy
```

## Consumers

Primary consumer: `Torotin/3x-ui_pro_Docker` (`docker-proxy/compose.d/05-caddy.yml`). Stack routing and Traefik labels live there, not in this image README.
