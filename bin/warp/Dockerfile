# ========================================================
# Stage: Builder
# ========================================================
FROM golang:alpine AS builder
WORKDIR /app
ARG TARGETARCH

RUN apk --no-cache --update add \
  build-base \
  gcc \
  wget \
  unzip

COPY . .

RUN go build -v -o build/ -trimpath -ldflags "-s -w" ./cmd/warp-plus
RUN mkdir -p /etc/warp/

# ========================================================
# Stage: Final Image
# ========================================================
FROM alpine
ENV TZ=Europe/Moscow

WORKDIR /app
VOLUME [ "/etc/warp/" ]

# Установка tzdata для поддержки таймзоны
RUN apk --no-cache add tzdata jq

COPY --from=builder /app/build/warp-plus /usr/bin/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/example_config.json /app/config.json.template

RUN chmod +x \
  /usr/bin/warp-plus \
  /app/DockerEntrypoint.sh

ENTRYPOINT [ "./DockerEntrypoint.sh" ]
