FROM alpine
WORKDIR /app
VOLUME [ "/etc/warp/" ]
RUN mkdir -p /etc/warp/cache

RUN apk add --no-cache ca-certificates curl jq coreutils tzdata libcap tar

COPY warp-plus /app/warp-plus
COPY DockerEntrypoint.sh /app/

RUN chmod +x \
    /app/warp-plus \
    /app/DockerEntrypoint.sh

EXPOSE 1080

# Внутренний healthcheck есть в скрипте, но можно и docker HEALTHCHECK (не обязательно)
# HEALTHCHECK --interval=5m --timeout=30s --start-period=1m \
#   CMD wget -qO- --proxy=on http://127.0.0.1:1080 || exit 1

ENTRYPOINT ["/app/DockerEntrypoint.sh"]
CMD []
