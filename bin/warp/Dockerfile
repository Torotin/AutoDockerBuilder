# Пин версию alpine для воспроизводимости
FROM alpine:3.20

WORKDIR /app
VOLUME [ "/etc/warp/" ]

# Добавим нужные утилиты; coreutils опционален, но полезен (shuf, od и т.д.)
RUN apk add --no-cache tzdata jq curl ca-certificates coreutils && update-ca-certificates

COPY ./warp-plus /usr/bin/
COPY ./DockerEntrypoint.sh /app/

RUN chmod +x /usr/bin/warp-plus /app/DockerEntrypoint.sh

EXPOSE 1080

# Можно включить nativе Docker HEALTHCHECK (проще для оркестраторов):
# HEALTHCHECK --interval=1m --timeout=10s --start-period=30s --retries=3 \
#   CMD sh -c ': "${HEALTHCHECK_URL:=https://ifconfig.me}"; \
#              : "${BIND:=0.0.0.0:1080}"; \
#              port="${BIND##*:}"; \
#              curl --socks5-hostname 127.0.0.1:${port} -sf --max-time 8 "$HEALTHCHECK_URL" >/dev/null || exit 1'

ENTRYPOINT [ "/app/DockerEntrypoint.sh" ]
