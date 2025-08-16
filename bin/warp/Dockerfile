# --- stage: build ---
ARG GO_VERSION=1.24
FROM golang:${GO_VERSION}-bookworm AS build

WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git && rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 https://github.com/bepass-org/warp-plus.git .

ENV CGO_ENABLED=0
ARG GIT_REF=manual
RUN go build -v -o /out/ -trimpath \
  -ldflags "-s -w -buildid= -checklinkname=0 -X main.version=${GIT_REF}" ./cmd/warp-plus && \
    go build -v -o /out/ -trimpath \
  -ldflags "-s -w -buildid= -checklinkname=0 -X main.version=${GIT_REF}" ./cmd/warp-scan

# --- stage: runtime ---
FROM alpine:3.20

# Требуемые рантайм-пакеты: сертификаты, curl, jq, shuf (из coreutils), tzdata, libcap
RUN apk add --no-cache ca-certificates curl jq coreutils tzdata libcap

# Система/права
RUN mkdir -p /etc/warp/cache

# Бинарники
COPY --from=build /out/warp-plus /usr/bin/warp-plus
COPY --from=build /out/warp-scan /usr/bin/warp-scan
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