# ========================================================
# Stage: Builder
# ========================================================
FROM golang:1.22-alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk --no-cache --update add \
  build-base \
  gcc \
  wget \
  unzip

# Кэшируем зависимости
COPY go.mod go.sum ./
RUN go mod download

# Копируем исходники
COPY . .

# Статическая сборка без CGO
RUN go build -v -o build/ -trimpath -ldflags "-s -w" ./cmd/warp-plus
RUN mkdir -p /etc/warp/

# ========================================================
# Stage: Final Image of warp-plus
# ========================================================
FROM alpine
RUN apk --no-cache --update add \
  build-base \
  gcc \
  wget \
  unzip \
  ca-certificates \
  socat \
  curl
  && update-ca-certificates

ENV TZ=Europe/Moscow

WORKDIR /app
VOLUME [ "/etc/warp/" ]

# Копируем бинарник и вспомогательные файлы
COPY --from=builder /build/warp-plus           /usr/bin/warp-plus
COPY --from=builder /build/DockerEntrypoint.sh /usr/local/bin/
COPY --from=builder /build/example_config.json /etc/warp/

# Даём права на выполнение
RUN chmod +x \
      /usr/bin/warp-plus \
      /usr/local/bin/DockerEntrypoint.sh

ENTRYPOINT ["/usr/local/bin/DockerEntrypoint.sh"]