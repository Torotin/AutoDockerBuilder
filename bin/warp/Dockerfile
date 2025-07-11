# ========================================================
# Stage: Builder
# ========================================================
FROM golang:alpine AS builder

ARG TARGETARCH
ENV TZ=Europe/Moscow

# Основная рабочая директория
WORKDIR /app

# Устанавливаем зависимости
RUN apk --no-cache --update add \
  build-base \
  gcc \
  wget \
  unzip \
  tzdata \
  jq \
  git

# Копируем только содержимое workdir (а не весь .git-обёрнутый корень)
COPY ./workdir/ ./

# Сборка бинарника
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

RUN apk --no-cache add tzdata jq

COPY --from=builder /app/build/warp-plus /usr/bin/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/example_config.json /app/config.json.template

RUN chmod +x \
  /usr/bin/warp-plus \
  /app/DockerEntrypoint.sh

ENTRYPOINT [ "./DockerEntrypoint.sh" ]
