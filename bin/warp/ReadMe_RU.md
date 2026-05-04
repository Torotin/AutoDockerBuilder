# 🌀 Warp Plus Docker

Контейнер для запуска [warp-plus](https://github.com/bepass-org/warp-plus) с гибкой конфигурацией через переменные окружения. Поддерживает динамическую генерацию конфигурационного файла `config.json` при старте, маршрутизацию через SOCKS5, выбор страны, режимы gool/psiphon, автоматические healthcheck-и и многое другое.

---

## 📦 Быстрый старт

```yml
services:
  warp:
    container_name: warp
    image: torotin/warp-plus:latest
    restart: unless-stopped
    cap_add:
      - NET_ADMIN

    ports:
      - "1080:1080"  # SOCKS5-прокси

    environment:
      KEY: ""                    # 🔑 Warp+ ключ
      ENDPOINT: ""              # 📍 Warp-endpoint
      BIND: "0.0.0.0:1080"      # 🌐 Интерфейс SOCKS5
      COUNTRY: ""               # 🗺 Страна (если не задан — выбирается случайно)
      EXCLUDE_COUNTRY: "RU IR CN"

      VERBOSE: "false"          # подробный лог
      GOOL: "false"             # warp внутри warp
      CFON: "false"             # режим psiphon
      SCAN: "true"              # сканирование endpoint'ов
      RTT: "1s"                 # порог времени отклика
      DNS: "9.9.9.9"            # DNS-сервер
      CACHE_DIR: "/etc/warp/cache/"
      FWMARK: "0x1375"
      WGCONF: ""                # путь к WireGuard-конфигу
      RESERVED: ""              # необязательное поле (используется warp-plus)
      TEST_URL: ""              # URL для проверки

      IPV4: "false"             # IPv4 режим (true/false)
      IPV6: "false"             # IPv6 режим (true/false)

    volumes:
      - ./warp-data:/etc/warp   # конфиг и кэш

    healthcheck:
      test: ["CMD", "curl", "--socks5", "localhost:1080", "--max-time", "5", "https://ifconfig.me"]
      interval: 30s
      timeout: 10s
      retries: 3
```

После запуска SOCKS5-прокси будет доступен по адресу `127.0.0.1:1080`.

## 🔍 Проверка IP

```bash
curl --socks5 127.0.0.1:1080 https://ifconfig.me
```

## ⚙️ Переменные окружения

| Переменная        | Тип    | По умолчанию       | Описание                                                 |
| ----------------- | ------ | ------------------ | -------------------------------------------------------- |
| `KEY`             | string | *(не задан)*          | 🔑 Warp+ ключ (не обязателен, но желателен)              |
| `ENDPOINT`        | string | *(не задан)*          | Конкретный Warp-endpoint (например `162.159.192.1:2408`) |
| `BIND`            | string | `0.0.0.0:1080`     | Адрес SOCKS-прокси                                       |
| `VERBOSE`         | bool   | `false`            | Включить подробный лог                                   |
| `DNS`             | string | `9.9.9.9`          | DNS-сервер                                               |
| `GOOL`            | bool   | `false`            | Режим warp-in-warp                                       |
| `CFON`            | bool   | `false`            | Режим psiphon                                            |
| `COUNTRY`         | string | *(выбирается)*     | Страна (ISO-код). Случайно, если не указана              |
| `EXCLUDE_COUNTRY` | string | `RU IR CN`         | Страны, исключённые из случайного выбора                 |
| `SCAN`            | bool   | `true`             | Сканировать endpoint'ы                                   |
| `RTT`             | string | `1s`               | Порог времени отклика                                    |
| `CACHE_DIR`       | string | `/etc/warp/cache/` | Путь для кэша warp-plus                                  |
| `FWMARK`          | string | `0x1375`           | fwmark для туннельного режима                            |
| `WGCONF`          | string | *(не задан)*          | Путь к wireguard-конфигу                                 |
| `RESERVED`        | string | *(не задан)*          | Дополнительное поле для warp-plus                        |
| `TEST_URL`        | string | *(не задан)*          | URL для ручной проверки соединения                       |
| `IPV4`            | bool   | `false`            | Использовать только IPv4 (взаимоисключимо с `IPV6`)      |
| `IPV6`            | bool   | `false`            | Использовать только IPv6 (взаимоисключимо с `IPV4`)      |

❗Контейнер сам адаптируется к среде:

- Если включены или отключены оба режима `GOOL` и `CFON` — случайно отключается один из них.
- Если включены или отключены оба протокола (`IPV4` и `IPV6`) — происходит случайный выбор протокола.
- Если включён `IPV6`, но функционал ipv6 недоступен — контейнер сам переключится на `IPV4`.


---

## ❤️ Внутренние переменные Healthcheck

| Переменная                  | По умолчанию          | Описание                                                      |
| --------------------------- | --------------------- | ------------------------------------------------------------- |
| `HEALTHCHECK_INTERVAL`      | `300`                 | Интервал между проверками (секунды)                           |
| `HEALTHCHECK_TIMEOUT`       | `30`                  | Таймаут ожидания ответа (секунды)                             |
| `HEALTHCHECK_INITIAL_DELAY` | `60`                  | Задержка перед первой проверкой                               |
| `HEALTHCHECK_MAX_FAILURES`  | `3`                   | Кол-во ошибок до перезапуска                                  |
| `HEALTHCHECK_URL`           | `https://ifconfig.me` | URL, через который проверяется работоспособность через SOCKS5 |

ℹ️ Встроенная проверка работает в фоне и, при ошибках, завершает процесс, что приводит к перезапуску контейнера (если `restart: unless-stopped` или подобный параметр установлен).
