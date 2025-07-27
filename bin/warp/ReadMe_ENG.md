# 🌀 Warp Plus Docker

A containerized setup for [warp-plus](https://github.com/bepass-org/warp-plus) with flexible configuration via environment variables. Supports dynamic generation of `config.json` at startup, routing via SOCKS5, country selection, gool/psiphon modes, built-in healthchecks, and more.

## 📦 Quick Start

```yml
services:
  warp:
    container_name: warp
    image: torotin/warp-plus:latest
    restart: unless-stopped
    cap_add:
      - NET_ADMIN

    ports:
      - "1080:1080"  # SOCKS5 proxy

    environment:
      KEY: ""                    # 🔑 Warp+ license key
      ENDPOINT: ""              # 📍 Warp endpoint
      BIND: "0.0.0.0:1080"      # 🌐 SOCKS5 bind address
      COUNTRY: ""               # 🗺 Country (random if not set)
      EXCLUDE_COUNTRY: "RU IR CN"

      VERBOSE: "false"          # verbose logging
      GOOL: "false"             # warp-in-warp mode
      CFON: "false"             # psiphon mode
      SCAN: "true"              # scan endpoints
      RTT: "1s"                 # RTT threshold
      DNS: "9.9.9.9"            # DNS server
      CACHE_DIR: "/etc/warp/cache/"
      FWMARK: "0x1375"
      WGCONF: ""                # wireguard config path
      RESERVED: ""              # optional warp-plus parameter
      TEST_URL: ""              # test connection URL

      IPV4: "false"             # IPv4 mode (true/false)
      IPV6: "false"             # IPv6 mode (true/false)

    volumes:
      - ./warp-data:/etc/warp   # config and cache

    healthcheck:
      test: ["CMD", "curl", "--socks5", "localhost:1080", "--max-time", "5", "https://ifconfig.me"]
      interval: 30s
      timeout: 10s
      retries: 3
````

After launch, the SOCKS5 proxy will be available at `127.0.0.1:1080`.

## 🔍 IP Check

```bash
curl --socks5 127.0.0.1:1080 https://ifconfig.me
```

## ⚙️ Environment Variables

| Variable          | Type   | Default            | Description                                     |
| ----------------- | ------ | ------------------ | ----------------------------------------------- |
| `KEY`             | string | *(unset)*          | 🔑 Warp+ license key (optional but recommended) |
| `ENDPOINT`        | string | *(unset)*          | Warp endpoint (e.g. `162.159.192.1:2408`)       |
| `BIND`            | string | `0.0.0.0:1080`     | SOCKS5 bind address                             |
| `VERBOSE`         | bool   | `false`            | Enable verbose logging                          |
| `DNS`             | string | `9.9.9.9`          | DNS server                                      |
| `GOOL`            | bool   | `false`            | Warp-in-warp mode (conflicts with `CFON`)       |
| `CFON`            | bool   | `false`            | Psiphon mode (conflicts with `GOOL`)            |
| `COUNTRY`         | string | *(random)*         | Country (ISO alpha-2 code), random if not set   |
| `EXCLUDE_COUNTRY` | string | `RU IR CN`         | Countries to exclude from random selection      |
| `SCAN`            | bool   | `true`             | Scan available endpoints                        |
| `RTT`             | string | `1s`               | Round-trip time threshold                       |
| `CACHE_DIR`       | string | `/etc/warp/cache/` | Cache path for warp-plus                        |
| `FWMARK`          | string | `0x1375`           | fwmark for tunnel mode (requires `NET_ADMIN`)   |
| `WGCONF`          | string | *(unset)*          | WireGuard config file path                      |
| `RESERVED`        | string | *(unset)*          | Additional field used by warp-plus              |
| `TEST_URL`        | string | *(unset)*          | Optional URL for manual testing                 |
| `IPV4`            | bool   | `false`            | Use only IPv4 (mutually exclusive with `IPV6`)  |
| `IPV6`            | bool   | `false`            | Use only IPv6 (mutually exclusive with `IPV4`)  |

---

> ❗The container adjusts automatically to the environment:
>
> * If both `GOOL` and `CFON` are set equally (`true/true` or `false/false`), one will be randomly disabled.
> * If both `IPV4` and `IPV6` are equal (either enabled or disabled), one will be randomly chosen.
> * If `IPV6=true` but no external IPv6 connectivity is available, the container will **automatically fallback to `IPV4`**.

---

## ❤️ Internal Healthcheck Parameters

| Variable                    | Default               | Description                                  |
| --------------------------- | --------------------- | -------------------------------------------- |
| `HEALTHCHECK_INTERVAL`      | `300`                 | Interval between checks (in seconds)         |
| `HEALTHCHECK_TIMEOUT`       | `30`                  | Timeout for response (in seconds)            |
| `HEALTHCHECK_INITIAL_DELAY` | `60`                  | Delay before the first check                 |
| `HEALTHCHECK_MAX_FAILURES`  | `3`                   | Restart threshold after consecutive failures |
| `HEALTHCHECK_URL`           | `https://ifconfig.me` | URL used for healthcheck via SOCKS5 proxy    |

ℹ️ Healthchecks are performed inside the container. On failure, the main process is terminated, which causes the container to restart (if using `restart: unless-stopped` or similar policy).
