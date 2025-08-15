# ========================================================
# Stage: Builder
# ========================================================
FROM golang:alpine AS builder

WORKDIR /app
RUN apk --no-cache add build-base gcc git tzdata jq

COPY . .

RUN mkdir -p build && \
    unset GOFLAGS && \
    go mod tidy && \
    go build -v -o build/ -trimpath -ldflags="-checklinkname=0 -s -w" ./cmd/warp-plus

RUN mkdir -p /etc/warp/

# ========================================================
# Stage: Final Image
# ========================================================
FROM alpine

ENV TZ=Europe/Moscow
WORKDIR /app
VOLUME [ "/etc/warp/" ]

RUN apk --no-cache add tzdata jq curl

COPY --from=builder /app/build/warp-plus /usr/bin/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/example_config.json /app/

RUN chmod +x \
    /usr/bin/warp-plus \
    /app/DockerEntrypoint.sh

# Документируем порт
EXPOSE 1080

# (опционально) Встраиваем docker HEALTHCHECK: проверка прокси на 127.0.0.1:1080
# Можно переопределить URL и тайминги через переменные окружения docker run.
HEALTHCHECK --interval=1m --timeout=10s --start-period=30s --retries=3 \
  CMD sh -c ': "${HEALTHCHECK_URL:=https://ifconfig.me}"; \
             curl --socks5 127.0.0.1:1080 -sf --max-time 8 "$HEALTHCHECK_URL" >/dev/null || exit 1'

ENTRYPOINT [ "./DockerEntrypoint.sh" ]
