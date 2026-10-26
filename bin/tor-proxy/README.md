# Tor Proxy (`torotin/tor-proxy`)

Комбинированный runtime: Tor + lyrebird (PT) + gost (SOCKS5/HTTP front) + dnsproxy (encrypted bootstrap DNS) + dnsmasq (DNS-over-Tor на `:53`).

| | |
| --- | --- |
| Docker Hub | `torotin/tor-proxy` |
| Workflow | `.github/workflows/TorProxy-Docker-selfhosted.yml` (отдельный pipeline, не `_docker-project-build`) |
| Files | `Dockerfile`, `entrypoint.sh`, `bridge-sync.sh`, `healthcheck.sh`, `docker-compose.tor-proxy.yml` |
| Platforms | `linux/amd64` only |

## Upstream components

| Component | Source |
| --- | --- |
| Tor | deb.torproject.org (pinned at build; optional soft-try upgrade at start) |
| lyrebird | built from tagged source in image build |
| gost | GitHub release asset + checksums.txt |
| dnsproxy | GitHub release asset + asset digest (sha256) |

Workflow resolves current stable versions and passes them as Dockerfile build args. Pinned `ARG` defaults in `Dockerfile` are for local builds only.

Bundled Tor Browser `pt_config.json` is fetched at build time from
`tor-browser-build` at commit `PT_CONFIG_REF` (CI resolves HEAD; Dockerfile
ships a default SHA for local builds). It is **not** part of the immutable
image tag. Runtime bridge feeds still refresh via `bridge-sync`.

Immutable image tag shape:

```text
tor-<tor-version>_lyrebird-<lyrebird-version>_gost-<gost-version>_dnsproxy-<dnsproxy-version>
```

Plus `:latest`.

## Image build notes

- Platforms: `linux/amd64` only
- `gnupg` is installed only long enough to import the Tor Project keyring, then purged; the keyring and `tor-project.list` remain for `TOR_UPDATE_ON_START`
- Primary CI verification is the image build itself (download + checksum + `jq` on `pt_config`), plus shellcheck / unit shell tests / layout asserts

## Architecture

```text
client → :1080 SOCKS5 / :8080 HTTP   (gost)
              └→ 127.0.0.1:9050      (tor SocksPort)
client → :53 TCP/UDP DNS             (dnsmasq → tor DNSPort 127.0.0.1:5353)
startup → dnsproxy on 127.0.0.1:53   (encrypted bootstrap DNS for feeds / PT)
bridges → lyrebird (obfs4, webtunnel, snowflake)
```

Volumes: `/var/lib/tor`, `/var/lib/tor-proxy` (bridge cache under `/var/lib/tor-proxy/bridges`).

Healthcheck: SOCKS5 to `https://check.torproject.org/api/ip`, expects `IsTor == true`.
Image/compose defaults: `start_period=3m`, `interval=30s`, `timeout=20s`, `retries=10`
(failures during `start_period` do not count toward `retries`).

## Endpoints

| Endpoint | Purpose |
| --- | --- |
| `tor-proxy:53` TCP/UDP | DNS via Tor (inside Docker network) |
| `tor-proxy:1080` | SOCKS5 |
| `tor-proxy:8080` | HTTP proxy |

Sample compose publishes host ports only on `127.0.0.1`. Peer containers should use the hostname `tor-proxy` and **not** require host publish.

```bash
curl --fail --silent --socks5-hostname tor-proxy:1080 \
  https://check.torproject.org/api/ip | grep '"IsTor":true'
```

## Environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `TOR_BRIDGES_ENABLED` | `true` | enable bridges at start |
| `TOR_BRIDGE_TRANSPORT` | `auto` | `auto`, `obfs4`, `webtunnel`, or `snowflake` |
| `TOR_BRIDGES_MAX_PER_TRANSPORT` | `2` | max bridge lines per transport (CPU guard) |
| `TOR_MAX_CLIENT_CIRCUITS_PENDING` | `4` | Tor `MaxClientCircuitsPending` |
| `TOR_IPV6_AVAILABLE` | `auto` | allow IPv6 bridge endpoints only if outbound IPv6 works |
| `TOR_BRIDGES_OBFS4_URL` | Tor-Bridges-Collector | `obfs4` feed |
| `TOR_BRIDGES_OBFS4_IPV6_URL` | Tor-Bridges-Collector | IPv6 `obfs4` feed |
| `TOR_BRIDGES_WEBTUNNEL_URL` | Tor-Bridges-Collector | `webtunnel` feed |
| `TOR_BRIDGES_SNOWFLAKE_URL` | Tor Browser `pt_config.json` | `snowflake` feed |
| `TOR_BOOTSTRAP_DNS_ENABLED` | `true` | encrypted bootstrap DNS via dnsproxy |
| `TOR_BOOTSTRAP_DNS_UPSTREAMS` | AdGuard DoH/DoT/DoQ | dnsproxy upstreams (DNS stamps OK) |
| `TOR_BOOTSTRAP_DNS_BOOTSTRAPS` | `94.140.14.14:53 94.140.15.15:53` | resolve encrypted upstream hostnames |
| `TOR_BOOTSTRAP_DNS_PLAIN_FALLBACK` | `true` | allow plaintext fallback for bootstrap DNS |
| `TOR_BOOTSTRAP_DNS_FALLBACKS` | empty | explicit plaintext fallback resolvers |
| `TOR_UPDATE_ON_START` | `true` | try `apt` upgrade of Tor from official repo |
| `TOR_PROXY_LOGIN`, `TOR_PROXY_PASSWORD` | empty | optional SOCKS5/HTTP auth (set together) |
| `TOR_PROXY_CPUS`, `TOR_PROXY_MEMORY_LIMIT` | `0.75`, `512m` | compose resource hints |
| `TOR_PROXY_HEALTHCHECK_URL` | `https://check.torproject.org/api/ip` | healthcheck URL |
| `TOR_RUNTIME_CONFIG_ONLY` | `false` | generate config and exit (no daemons) |

### Bridge feed behavior

- Feeds are validated, deduped, cached under `/var/lib/tor-proxy`; download failure falls back to cache.
- Image ships bundled Tor Browser defaults for `obfs4` and `snowflake` (`pt_config.json`). `webtunnel` has **no** bundled fallback — explicit `webtunnel` without feed/cache fails start.
- Public `scriptzteam/Tor-Bridges-Collector` feeds are untrusted third-party sources; override via URL env vars if needed.
- `auto` keeps all three transports but samples at most `TOR_BRIDGES_MAX_PER_TRANSPORT` lines each.
- After validation, IPv4 bridge endpoints in private/reserved ranges are dropped:
  `0.0.0.0/8`, `10.0.0.0/8`, `127.0.0.0/8`, `169.254.0.0/16`, `172.16.0.0/12`, `192.168.0.0/16`.
  Snowflake `192.0.2.0/24` placeholders are **kept**.
- IPv6 bridge endpoints remain gated by outbound IPv6 availability (`TOR_IPV6_AVAILABLE`).

Published `:53` always forwards DNS **through Tor**. Encrypted dnsproxy is only for bootstrap/feed/PT name resolution; plaintext fallback applies only to that bootstrap path.

### Small VPS example `.env`

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

IPv6-only destinations on the SOCKS listener depend on Tor exit capability. IPv6 bridge endpoints are filtered when the VPS has no working outbound IPv6.

## Example compose

```bash
docker compose -f bin/tor-proxy/docker-compose.tor-proxy.yml up -d
```

## Consumers

Primary consumer: `Torotin/3x-ui_pro_Docker` (`docker-proxy/compose.d/11-tor-proxy.yml`).
That stack typically leaves host `ports:` commented and reaches `tor-proxy` over the Docker network.
If that stack raises `TOR_BRIDGES_MAX_PER_TRANSPORT` above this sample default (`2`), either lower MAX
toward `2` or lengthen health `start_period` / `retries` to match slower bridge selection under
`MaxClientCircuitsPending=4`. This repo does not change that consumer's compose files.
