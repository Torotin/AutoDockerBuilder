# 🌀 Warp Plus Docker

Контейнер для запуска [warp-plus](https://github.com/bepass-org/warp-plus) с возможностью гибкой конфигурации через переменные окружения. Поддерживает динамическую генерацию конфигурационного файла `config.json` на старте, маршрутизацию через SOCKS5, выбор страны, режим gool/psiphon и многое другое.

---

## 📦 Быстрый старт

```yml
services:
  warp:
    container_name: warp
    image: torotin/warp-plus:latest
    restart: unless-stopped

    ports:
      - "1080:1080"     # SOCKS5-прокси

    environment:
      # 🔑 Warp-ключ (необязателен, но нужен для полноценной работы)
      KEY: ""

      # 📍 Endpoint (например: 162.159.192.1:2408)
      ENDPOINT: ""

      # 🌐 Интерфейс прослушивания SOCKS5
      BIND: "0.0.0.0:1080"

      # 🗺 Страна (если не задана — выбирается случайная)
      COUNTRY: ""
      EXCLUDE_COUNTRY: "RU CN IR"

      # ⚙️ Технические флаги
      VERBOSE: "false"              # подробные логи
      GOOL: "false"                 # warp внутри warp
      CFON: "false"                 # режим psiphon
      SCAN: "true"                  # включить сканирование endpoint'ов
      RTT: "1s"                     # порог времени отклика
      DNS: "1.1.1.1"                # DNS-сервер
      CACHE_DIR: "/etc/warp/cache/" # путь для кэша
      FWMARK: "0x1375"              # fwmark для tun-mode (если нужно)
      WGCONF: ""                    # путь к wireguard-конфигу
      TEST_URL: ""                  # URL для тестирования подключения

      # 🌐 IP протокол
      IPV4: "true"                  # только IPv4 (по умолчанию true)
      IPV6: "false"                 # только IPv6 (если включено, то IPV4 должно быть false)

    volumes:
      - ./warp-data:/etc/warp      # конфиг и кэш

    healthcheck:
      test: ["CMD", "curl", "--socks5", "localhost:1080", "--max-time", "5", "https://ifconfig.me"]
      interval: 30s
      timeout: 10s
      retries: 3
```
После запуска SOCKS5‑прокси будет доступен по адресу `127.0.0.1:1080`.



## 🔍 Проверка IP

Проверь, какой IP используется через прокси:

```bash
curl --socks5 127.0.0.1:1080 https://ifconfig.me
```


## ⚙️ Переменные окружения
> ❗ Если `COUNTRY` не указан — будет выбран случайный из списка, исключая страны из `EXCLUDE_COUNTRY`.

| Переменная        | Тип    | По умолчанию       | Описание                                                 |
| ----------------- | ------ | ------------------ | -------------------------------------------------------- |
| `KEY`             | string | *(пусто)*          | 🔑 Warp+ ключ *(не обязателен, но необходим для работы)* |
| `ENDPOINT`        | string | *(пусто)*          | Конкретный Warp‑endpoint (например `162.159.192.1:2408`) |
| `BIND`            | string | `127.0.0.1:1080`   | Адрес SOCKS-прокси                                       |
| `VERBOSE`         | bool   | `false`            | Включить подробный лог                                   |
| `DNS`             | string | `1.1.1.1`          | DNS-сервер                                               |
| `GOOL`            | bool   | `false`            | Режим warp-in-warp                                       |
| `CFON`            | bool   | `false`            | Режим psiphon                                            |
| `COUNTRY`         | string | `AT` или случайно  | Страна (код ISO 3166-1 alpha-2)                          |
| `EXCLUDE_COUNTRY` | string | *(пусто)*          | Исключить страны из случайного выбора (`US DE FR`)       |
| `SCAN`            | bool   | `true`             | Сканировать endpoint'ы                                   |
| `RTT`             | string | `1s`               | Порог RTT                                                |
| `CACHE_DIR`       | string | `/etc/warp/cache/` | Кеш для сканера                                          |
| `FWMARK`          | string | `0x1375`           | Linux fwmark для tun-режима                              |
| `WGCONF`          | string | *(пусто)*          | Путь к wireguard конфигу                                 |
| `TEST_URL`        | string | *(пусто)*          | URL для проверки соединения                              |
| `IPV4`            | bool   | `true`             | Только IPv4 (взаимоисключимо с `IPV6`)                   |
| `IPV6`            | bool   | `false`            | Только IPv6 (взаимоисключимо с `IPV4`)                   |