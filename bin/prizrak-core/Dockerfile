FROM alpine:3.21

ARG PRIZRAK_REPO=legiz-ru/Prizrak-Core
ARG PRIZRAK_VERSION
ARG PRIZRAK_CORE_VARIANT=v3
ARG TARGETARCH

LABEL org.opencontainers.image.title="Prizrak-Core"
LABEL org.opencontainers.image.description="Prizrak-Core proxy with baked release binary, geo data, and in-container self-update"
LABEL org.opencontainers.image.source="https://github.com/legiz-ru/Prizrak-Core"

RUN apk add --no-cache \
    ca-certificates \
    curl \
    gzip \
    iptables \
    tzdata

COPY bin/prizrak-core/asset-name.sh /opt/prizrak/asset-name.sh
COPY bin/prizrak-core/healthcheck.sh /opt/prizrak/healthcheck.sh
COPY DockerEntrypoint.sh /opt/prizrak/DockerEntrypoint.sh
COPY update-core.sh /opt/prizrak/update-core.sh

RUN chmod +x /opt/prizrak/DockerEntrypoint.sh /opt/prizrak/update-core.sh /opt/prizrak/healthcheck.sh

RUN set -eux; \
    . /opt/prizrak/asset-name.sh; \
    test -n "${PRIZRAK_VERSION}"; \
    asset="$(prizrak_asset_name linux "${TARGETARCH}" "${PRIZRAK_CORE_VARIANT}" "${PRIZRAK_VERSION}")"; \
    release_url="https://github.com/${PRIZRAK_REPO}/releases/download/${PRIZRAK_VERSION}"; \
    mkdir -p /opt/prizrak/geo /root/.config/mihomo; \
    curl -fsSL "${release_url}/${asset}" | gzip -dc > /opt/prizrak/prizrak-core; \
    chmod +x /opt/prizrak/prizrak-core; \
    printf '%s\n' "${PRIZRAK_VERSION}" > /opt/prizrak/installed-release; \
    geo_base="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"; \
    for geo_asset in geoip.dat geosite.dat geoip.metadb; do \
        curl -fsSL -o "/opt/prizrak/geo/${geo_asset}" "${geo_base}/${geo_asset}"; \
        cp -f "/opt/prizrak/geo/${geo_asset}" "/root/.config/mihomo/${geo_asset}"; \
    done

VOLUME ["/root/.config/mihomo/"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD /opt/prizrak/healthcheck.sh

ENTRYPOINT ["/opt/prizrak/DockerEntrypoint.sh"]
