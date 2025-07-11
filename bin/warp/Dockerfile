# ========================================================
# Stage: Builder
# ========================================================
FROM golang:alpine AS builder

WORKDIR /app
ARG TARGETARCH

ENV GOFLAGS='-ldflags="-checklinkname=0 -s -w"'

RUN apk --no-cache --update add \
  build-base \
  gcc \
  wget \
  unzip \
  tzdata \
  jq \
  git

# Копируем исходники
COPY . .

# Создаём директорию для вывода
RUN mkdir -p build

# Сборка бинарника
RUN mkdir -p build && \
    unset GOFLAGS && \
    go build -v -o build/ -trimpath -ldflags="-checklinkname=0 -s -w" ./cmd/warp-plus

# Создаём директорию конфигов (на всякий случай)
RUN mkdir -p /etc/warp/

# ========================================================
# Stage: Final Image
# ========================================================
FROM alpine

ENV TZ=Europe/Moscow

WORKDIR /app
VOLUME [ "/etc/warp/" ]

# Установка зависимостей
RUN apk --no-cache add tzdata jq

# Копируем артефакты сборки
COPY --from=builder /app/build/warp-plus /usr/bin/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/example_config.json /app/config.json.template

# Делаем исполняемыми бинарники
RUN chmod +x \
  /usr/bin/warp-plus \
  /app/DockerEntrypoint.sh

# Точка входа
ENTRYPOINT [ "./DockerEntrypoint.sh" ]
