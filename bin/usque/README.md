# usque (`torotin/usque`)

Open-source Cloudflare WARP MASQUE client ([Diniboy1123/usque](https://github.com/Diniboy1123/usque)) as a SOCKS/HTTP/TUN helper image.

| | |
| --- | --- |
| Docker Hub | `torotin/usque` |
| Upstream | [Diniboy1123/usque](https://github.com/Diniboy1123/usque) |
| Workflow | `.github/workflows/usque-Docker-selfhosted.yml` |
| Prepare mode | `clone-release` → `./WORKDIR/usque` |
| Dockerfile / entrypoint | `bin/usque/Dockerfile`, `DockerEntrypoint.sh` |
| Example compose | `bin/usque/docker-compose.usque.yml` |
| Platforms | default `linux/amd64`, `linux/386`; also `linux/arm64/v8` |

## Upstream docs

- Repository README: [Diniboy1123/usque](https://github.com/Diniboy1123/usque)

## Runtime contract

```text
client → :1080 (default socks mode)
entrypoint registers WARP device on first start if config.json is empty
```

- Default command: `socks` (also supports `http-proxy`, `nativetun`, `portfw`, plus passthrough to `usque` CLI).
- Persist `config.json` across restarts (bind-mount a **file**, not a directory).
- Health idea (compose sample): SOCKS curl to Cloudflare trace must show `warp=on`.

### Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `USQUE_CONFIG` | `config.json` / `/app/config.json` | path to device config |
| `USQUE_DEVICE_NAME` | `usque-docker` | name used on first `register` |
| `USQUE_JWT` | empty | optional JWT for registration |
| `USQUE_EXTRA_ARGS` | empty | extra args appended for proxy modes |

## Example

See `docker-compose.usque.yml`. Minimal idea:

```bash
mkdir -p ./usque && touch ./usque/config.json
docker compose -f bin/usque/docker-compose.usque.yml up -d
```

## Consumers

Primary consumer: `Torotin/3x-ui_pro_Docker` (`docker-proxy/compose.d/09-usque.yml`) as WARP-like SOCKS egress for managed Xray. Do not confuse with a revived standalone `warp` container name.
