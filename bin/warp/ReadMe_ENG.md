# 🌀 Warp Plus Docker

A self-hosted Docker container for running [warp-plus](https://github.com/bepass-org/warp-plus) with flexible configuration via environment variables. Supports dynamic generation of `config.json`, routing through a local SOCKS5 proxy, country selection (with exclusions), gool/psiphon modes, endpoint scanning, and more.

---

## 📦 Quick Start

```yaml
services:
  warp:
    container_name: warp
    image: torotin/warp-plus:latest
    restart: unless-stopped

    ports:
      - "1080:1080"     # Exposes SOCKS5 proxy

    environment:
      # 🔑 Warp+ key (optional but required for full functionality)
      KEY: ""

      # 📍 Endpoint (e.g. 162.159.192.1:2408)
      ENDPOINT: ""

      # 🌐 SOCKS5 bind address
      BIND: "0.0.0.0:1080"

      # 🗺 Country (if not set — random country will be chosen)
      COUNTRY: ""
      EXCLUDE_COUNTRY: "RU CN IR"

      # ⚙️ Advanced flags
      VERBOSE: "false"             # Enable verbose logging
      GOOL: "false"                # Warp-in-Warp mode
      CFON: "false"                # Psiphon mode (requires COUNTRY)
      SCAN: "true"                 # Enable endpoint scanning
      RTT: "1s"                    # RTT threshold
      DNS: "1.1.1.1"               # DNS resolver
      CACHE_DIR: "/etc/warp/cache/" # Scanner cache path
      FWMARK: "0x1375"             # Linux fwmark for tun-mode (optional)
      WGCONF: ""                   # Path to WireGuard config
      TEST_URL: ""                 # Custom test URL

      # 🌐 Protocol
      IPV4: "true"                 # IPv4 only (default)
      IPV6: "false"                # IPv6 only (mutually exclusive with IPV4)

    volumes:
      - ./warp-data:/etc/warp     # Persist config/cache

    healthcheck:
      test: ["CMD", "curl", "--socks5", "localhost:1080", "--max-time", "5", "https://ifconfig.me"]
      interval: 30s
      timeout: 10s
      retries: 3
```

Once launched, the SOCKS5 proxy will be available at `127.0.0.1:1080`.

---

## 🔍 Verify Your Proxy IP

To check which IP is being used via the proxy:

```bash
curl --socks5 127.0.0.1:1080 https://ifconfig.me
```

---

## ⚙️ Environment Variables

> ℹ️ If `COUNTRY` is not set, a random one will be selected from the supported list, excluding any countries specified in `EXCLUDE_COUNTRY`.

| Variable          | Type   | Default            | Description                                                          |
| ----------------- | ------ | ------------------ | -------------------------------------------------------------------- |
| `KEY`             | string | *(empty)*          | 🔑 Warp+ license key *(optional but required for actual traffic)*    |
| `ENDPOINT`        | string | *(empty)*          | Custom Warp endpoint (e.g., `162.159.192.1:2408`)                    |
| `BIND`            | string | `127.0.0.1:1080`   | SOCKS5 proxy listen address                                          |
| `VERBOSE`         | bool   | `false`            | Enable verbose logs                                                  |
| `DNS`             | string | `1.1.1.1`          | DNS resolver                                                         |
| `GOOL`            | bool   | `false`            | Warp-in-Warp mode                                                    |
| `CFON`            | bool   | `false`            | Psiphon mode (must set `COUNTRY`)                                    |
| `COUNTRY`         | string | random or `"AT"`   | Country ISO code (from a supported list)                             |
| `EXCLUDE_COUNTRY` | string | *(empty)*          | Space/Comma-separated list of ISO codes to exclude (e.g. `US CN RU`) |
| `SCAN`            | bool   | `true`             | Enable endpoint scanning                                             |
| `RTT`             | string | `1s`               | RTT threshold for scanner                                            |
| `CACHE_DIR`       | string | `/etc/warp/cache/` | Directory to store endpoint cache                                    |
| `FWMARK`          | string | `0x1375`           | Linux fwmark for routing in tun-mode                                 |
| `WGCONF`          | string | *(empty)*          | Path to a WireGuard config file                                      |
| `TEST_URL`        | string | *(empty)*          | URL used to verify connectivity                                      |
| `IPV4`            | bool   | `true`             | Use only IPv4 (mutually exclusive with `IPV6`)                       |
| `IPV6`            | bool   | `false`            | Use only IPv6 (mutually exclusive with `IPV4`)                       |
