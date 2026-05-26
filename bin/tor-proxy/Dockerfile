ARG DEBIAN_VERSION=13-slim
ARG LYREBIRD_VERSION=0.8.1
ARG GOST_VERSION=3.2.6

FROM golang:1.24-bookworm AS lyrebird-builder
ARG LYREBIRD_VERSION
RUN apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates git make; \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "lyrebird-${LYREBIRD_VERSION}" \
        https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/lyrebird.git /src/lyrebird; \
    make -C /src/lyrebird build; \
    install -m 0755 /src/lyrebird/lyrebird /usr/local/bin/lyrebird

FROM debian:${DEBIAN_VERSION} AS gost-download
ARG GOST_VERSION
RUN apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl tar; \
    rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    asset="gost_${GOST_VERSION}_linux_amd64.tar.gz"; \
    base_url="https://github.com/go-gost/gost/releases/download/v${GOST_VERSION}"; \
    curl -fL --retry 5 "${base_url}/${asset}" -o "/tmp/${asset}"; \
    curl -fL --retry 5 "${base_url}/checksums.txt" -o /tmp/checksums.txt; \
    cd /tmp; \
    grep " ${asset}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "${asset}"; \
    install -m 0755 gost /usr/local/bin/gost

FROM debian:${DEBIAN_VERSION}
ARG TOR_VERSION=0.4.9.8-1~d13.trixie+1
ARG LYREBIRD_VERSION
ARG GOST_VERSION

LABEL org.opencontainers.image.title="Tor Proxy"
LABEL org.opencontainers.image.description="Tor DNS, SOCKS5 and HTTP proxy with refreshed bridge feeds"
LABEL org.opencontainers.image.version="tor-${TOR_VERSION}_lyrebird-${LYREBIRD_VERSION}_gost-${GOST_VERSION}"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        coreutils \
        curl \
        dnsmasq \
        gnupg \
        jq \
        tini; \
    curl -fsSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
        | gpg --dearmor -o /usr/share/keyrings/deb.torproject.org-keyring.gpg; \
    printf '%s\n' \
        'deb [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org trixie main' \
        > /etc/apt/sources.list.d/tor-project.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends "tor=${TOR_VERSION}"; \
    rm -rf /var/lib/apt/lists/*

COPY --from=lyrebird-builder /usr/local/bin/lyrebird /usr/local/bin/lyrebird
COPY --from=gost-download /usr/local/bin/gost /usr/local/bin/gost
COPY bridge-sync.sh /usr/local/bin/tor-proxy-bridge-sync
COPY entrypoint.sh /usr/local/bin/tor-proxy-entrypoint
COPY healthcheck.sh /usr/local/bin/tor-proxy-healthcheck

RUN set -eux; \
    chmod 0755 /usr/local/bin/tor-proxy-bridge-sync \
        /usr/local/bin/tor-proxy-entrypoint \
        /usr/local/bin/tor-proxy-healthcheck; \
    mkdir -p /usr/local/share/tor-proxy /var/lib/tor-proxy /etc/tor; \
    curl -fsSL \
        https://gitlab.torproject.org/tpo/applications/tor-browser-build/-/raw/main/projects/tor-expert-bundle/pt_config.json \
        -o /usr/local/share/tor-proxy/pt_config.json; \
    jq -e '(.bridges.obfs4 | length > 0) and (.bridges.snowflake | length > 0)' \
        /usr/local/share/tor-proxy/pt_config.json >/dev/null; \
    test -x /usr/local/bin/lyrebird; \
    test -x /usr/local/bin/gost

VOLUME ["/var/lib/tor", "/var/lib/tor-proxy"]

EXPOSE 53/tcp 53/udp 1080/tcp 8080/tcp

HEALTHCHECK --interval=1m --timeout=20s --start-period=1m --retries=3 \
    CMD ["/usr/local/bin/tor-proxy-healthcheck"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/tor-proxy-entrypoint"]
