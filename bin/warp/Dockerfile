FROM alpine:3.20

# Требуемые рантайм-пакеты: сертификаты, curl, jq, shuf (из coreutils), tzdata, libcap, tar
RUN apk add --no-cache ca-certificates curl jq coreutils tzdata libcap tar

# Система/права
RUN mkdir -p /etc/warp/cache

# Загрузка готовых бинарников
ARG WARP_VERSION=0.0.0
RUN curl -L -o /tmp/warp.tar.gz \
    https://github.com/bepass-org/warp-plus/releases/download/${WARP_VERSION}/warp-plus_${WARP_VERSION}_linux_amd64.tar.gz \
    && tar -xzf /tmp/warp.tar.gz -C /usr/bin warp-plus warp-scan \
    && rm /tmp/warp.tar.gz

# Права на бинарники
RUN setcap CAP_NET_ADMIN,CAP_NET_RAW+eip /usr/bin/warp-plus \
    && setcap CAP_NET_ADMIN,CAP_NET_RAW+eip /usr/bin/warp-scan

# Твой entrypoint
COPY DockerEntrypoint.sh /usr/local/bin/warp-entry.sh
RUN chmod +x /usr/local/bin/warp-entry.sh
WORKDIR /app
EXPOSE 1080

# Внутренний healthcheck есть в скрипте, но можно и docker HEALTHCHECK (не обязательно)
# HEALTHCHECK --interval=5m --timeout=30s --start-period=1m \
#   CMD wget -qO- --proxy=on http://127.0.0.1:1080 || exit 1

ENTRYPOINT ["/usr/local/bin/warp-entry.sh"]
CMD []
