#!/bin/sh
set -eu

DOCKCHECK_WORKDIR="${DOCKCHECK_WORKDIR:-/_dockcheck}"
DOCKCHECK_SEED_DIR="${DOCKCHECK_SEED_DIR:-/usr/local/share/dockcheck-seed}"
DOCKCHECK_REF="${DOCKCHECK_REF:-main}"
DOCKCHECK_RAW_URL="${DOCKCHECK_RAW_URL:-https://raw.githubusercontent.com/mag37/dockcheck/${DOCKCHECK_REF}}"
DOCKCHECK_COMPOSE_DIR="${DOCKCHECK_COMPOSE_DIR:-/compose.d}"
DOCKCHECK_COMPOSE_ENV="${DOCKCHECK_COMPOSE_ENV:-/compose.d/.env}"
DOCKCHECK_COMPOSE_SERVICE="${DOCKCHECK_COMPOSE_SERVICE:-dockcheck}"
REGCTL_VERSION="${REGCTL_VERSION:-latest}"

set_default_env() {
  : "${TZ:=UTC}"
  : "${WEBDOMAIN:=dockcheck}"
  : "${DOCKCHECK_ENV_FILE:=/compose.d/.env}"
  : "${DOCKCHECK_INTERVAL:=24h}"
  : "${DOCKCHECK_INITIAL_DELAY_SECONDS:=30}"
  : "${DOCKCHECK_SCRIPTUPDATE:=false}"
  : "${DOCKCHECK_CONTAINER_SELFUPDATE:=false}"
  : "${DOCKCHECK_COMPOSE_DIR:=/compose.d}"
  : "${DOCKCHECK_COMPOSE_ENV:=/compose.d/.env}"
  : "${DOCKCHECK_COMPOSE_SERVICE:=dockcheck}"
  : "${DOCKCHECK_WORKDIR:=/_dockcheck}"
  : "${DOCKCHECK_SEED_DIR:=/usr/local/share/dockcheck-seed}"
  : "${DOCKCHECK_REF:=main}"
  : "${DOCKCHECK_RAW_URL:=https://raw.githubusercontent.com/mag37/dockcheck/${DOCKCHECK_REF}}"
  : "${REGCTL_VERSION:=latest}"

  : "${DOCKCHECK_AUTOMODE:=true}"
  : "${DOCKCHECK_AUTOPRUNE:=false}"
  : "${DOCKCHECK_AUTOSELFUPDATE:=false}"
  : "${DOCKCHECK_BACKUPFORDAYS:=}"
  : "${DOCKCHECK_BARWIDTH:=50}"
  : "${DOCKCHECK_COLLECTORTEXTFILEDIRECTORY:=}"
  : "${DOCKCHECK_CURLCONNECTTIMEOUT:=5}"
  : "${DOCKCHECK_CURLRETRYCOUNT:=3}"
  : "${DOCKCHECK_CURLRETRYDELAY:=1}"
  : "${DOCKCHECK_DAYSOLD:=}"
  : "${DOCKCHECK_DISPLAYSOURCEDFILES:=false}"
  : "${DOCKCHECK_DONTUPDATE:=false}"
  : "${DOCKCHECK_DRUNUP:=false}"
  : "${DOCKCHECK_EXCLUDE:=dockcheck}"
  : "${DOCKCHECK_FORCERESTARTSTACKS:=false}"
  : "${DOCKCHECK_MAXASYNC:=10}"
  : "${DOCKCHECK_MONOMODE:=false}"
  : "${DOCKCHECK_NOTIFY:=false}"
  : "${DOCKCHECK_ONLYSHOWUPDATEABLE:=false}"
  : "${DOCKCHECK_ONLYLABEL:=false}"
  : "${DOCKCHECK_ONLYSPECIFIC:=true}"
  : "${DOCKCHECK_PRINTMARKDOWNURL:=false}"
  : "${DOCKCHECK_PRINTRELEASEURL:=false}"
  : "${DOCKCHECK_SKIPRECREATE:=false}"
  : "${DOCKCHECK_STOPPED:=}"
  : "${DOCKCHECK_TIMEOUT:=10}"
  : "${DOCKCHECK_CONFIG_APPEND:=}"

  : "${DOCKCHECK_NOTIFY_CHANNELS:=}"
  : "${DOCKCHECK_SNOOZE_SECONDS:=}"
  : "${DOCKCHECK_DISABLE_DOCKCHECK_NOTIFICATION:=false}"
  : "${DOCKCHECK_DISABLE_NOTIFY_NOTIFICATION:=false}"

  : "${DOCKCHECK_APPRISE_PAYLOAD:=}"
  : "${DOCKCHECK_APPRISE_URL:=}"
  : "${DOCKCHECK_APPRISE_TAG:=}"
  : "${DOCKCHECK_BARK_KEY:=}"
  : "${DOCKCHECK_DISCORD_WEBHOOK_URL:=}"
  : "${DOCKCHECK_DSM_SENDMAILTO:=}"
  : "${DOCKCHECK_DSM_SUBJECTTAG:=}"
  : "${DOCKCHECK_FILE_PATH:=}"
  : "${DOCKCHECK_GOTIFY_DOMAIN:=}"
  : "${DOCKCHECK_GOTIFY_TOKEN:=}"
  : "${DOCKCHECK_HA_ENTITY:=}"
  : "${DOCKCHECK_HA_TOKEN:=}"
  : "${DOCKCHECK_HA_URL:=}"
  : "${DOCKCHECK_MATRIX_ACCESS_TOKEN:=}"
  : "${DOCKCHECK_MATRIX_ROOM_ID:=}"
  : "${DOCKCHECK_MATRIX_SERVER_URL:=}"
  : "${DOCKCHECK_NTFY_DOMAIN:=}"
  : "${DOCKCHECK_NTFY_TOPIC_NAME:=}"
  : "${DOCKCHECK_NTFY_AUTH:=}"
  : "${DOCKCHECK_PUSHBULLET_URL:=}"
  : "${DOCKCHECK_PUSHBULLET_TOKEN:=}"
  : "${DOCKCHECK_PUSHOVER_URL:=}"
  : "${DOCKCHECK_PUSHOVER_USER_KEY:=}"
  : "${DOCKCHECK_PUSHOVER_TOKEN:=}"
  : "${DOCKCHECK_SLACK_CHANNEL_ID:=}"
  : "${DOCKCHECK_SLACK_ACCESS_TOKEN:=}"
  : "${DOCKCHECK_SMTP_MAIL_FROM:=}"
  : "${DOCKCHECK_SMTP_MAIL_TO:=}"
  : "${DOCKCHECK_SMTP_SUBJECT_TAG:=}"
  : "${DOCKCHECK_TELEGRAM_CHAT_ID:=}"
  : "${DOCKCHECK_TELEGRAM_TOKEN:=}"
  : "${DOCKCHECK_TELEGRAM_TOPIC_ID:=}"
  : "${DOCKCHECK_XMPP_SOURCE_JID:=}"
  : "${DOCKCHECK_XMPP_SOURCE_PWD:=}"
  : "${DOCKCHECK_XMPP_DEST_JID:=}"

  export TZ WEBDOMAIN DOCKCHECK_ENV_FILE DOCKCHECK_INTERVAL DOCKCHECK_INITIAL_DELAY_SECONDS
  export DOCKCHECK_SCRIPTUPDATE DOCKCHECK_CONTAINER_SELFUPDATE DOCKCHECK_COMPOSE_DIR
  export DOCKCHECK_COMPOSE_ENV DOCKCHECK_COMPOSE_SERVICE DOCKCHECK_WORKDIR DOCKCHECK_SEED_DIR
  export DOCKCHECK_REF DOCKCHECK_RAW_URL REGCTL_VERSION
}

NOTIFY_TEMPLATE_FILES="
notify_DSM.sh
notify_HA.sh
notify_apprise.sh
notify_bark.sh
notify_discord.sh
notify_file.sh
notify_generic.sh
notify_gotify.sh
notify_matrix.sh
notify_ntfy.sh
notify_pushbullet.sh
notify_pushover.sh
notify_slack.sh
notify_smtp.sh
notify_telegram.sh
notify_v2.sh
notify_xmpp.sh
urls.list
"

log() {
  printf '[dockcheck] %s\n' "$*"
}

is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|y|on|да|д) return 0 ;;
    *) return 1 ;;
  esac
}

quote_config_value() {
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

write_config_var() {
  name="$1"
  value="${2:-}"
  [ -n "$value" ] || return 0
  printf '%s=%s\n' "$name" "$(quote_config_value "$value")" >> "${DOCKCHECK_WORKDIR}/dockcheck.config"
}

write_prefixed_config_var() {
  config_name="$1"
  env_name="$2"
  eval "value=\${${env_name}:-}"
  write_config_var "$config_name" "$value"
}

download_file() {
  url="$1"
  output="$2"
  tmp="${output}.tmp"

  if curl -fsSL "$url" -o "$tmp"; then
    mv -f "$tmp" "$output"
    return 0
  fi

  rm -f "$tmp"
  log "WARN: failed to download $url"
  return 1
}

seed_workdir() {
  mkdir -p "${DOCKCHECK_WORKDIR}"

  if [ ! -s "${DOCKCHECK_WORKDIR}/dockcheck.sh" ] && [ -d "$DOCKCHECK_SEED_DIR" ]; then
    cp -a "${DOCKCHECK_SEED_DIR}/." "${DOCKCHECK_WORKDIR}/"
  fi

  mkdir -p "${DOCKCHECK_WORKDIR}/notify_templates" "${DOCKCHECK_WORKDIR}/addons/prometheus"
  chmod +x "${DOCKCHECK_WORKDIR}/dockcheck.sh" 2>/dev/null || true
  chmod +x "${DOCKCHECK_WORKDIR}"/notify_templates/*.sh 2>/dev/null || true
}

sync_dockcheck_files() {
  is_true "${DOCKCHECK_SCRIPTUPDATE:-false}" || return 0

  log "syncing dockcheck runtime files from ${DOCKCHECK_RAW_URL}"
  download_file "${DOCKCHECK_RAW_URL}/dockcheck.sh" "${DOCKCHECK_WORKDIR}/dockcheck.sh" || true
  download_file "${DOCKCHECK_RAW_URL}/default.config" "${DOCKCHECK_WORKDIR}/default.config" || true
  download_file "${DOCKCHECK_RAW_URL}/addons/prometheus/prometheus_collector.sh" "${DOCKCHECK_WORKDIR}/addons/prometheus/prometheus_collector.sh" || true

  for file in $NOTIFY_TEMPLATE_FILES; do
    download_file "${DOCKCHECK_RAW_URL}/notify_templates/${file}" "${DOCKCHECK_WORKDIR}/notify_templates/${file}" || true
  done

  if [ -s "${DOCKCHECK_WORKDIR}/notify_templates/urls.list" ]; then
    cp -f "${DOCKCHECK_WORKDIR}/notify_templates/urls.list" "${DOCKCHECK_WORKDIR}/urls.list"
  fi

  chmod +x "${DOCKCHECK_WORKDIR}/dockcheck.sh" 2>/dev/null || true
  chmod +x "${DOCKCHECK_WORKDIR}"/notify_templates/*.sh 2>/dev/null || true
  chmod +x "${DOCKCHECK_WORKDIR}/addons/prometheus/prometheus_collector.sh" 2>/dev/null || true
}

ensure_regctl() {
  if command -v regctl >/dev/null 2>&1 || [ -x "${DOCKCHECK_WORKDIR}/regctl" ]; then
    return 0
  fi

  case "$(uname -m)" in
    x86_64) regctl_arch="amd64" ;;
    aarch64|arm64) regctl_arch="arm64" ;;
    *)
      log "WARN: unsupported architecture for regctl: $(uname -m)"
      return 0
      ;;
  esac

  if [ "$REGCTL_VERSION" = "latest" ]; then
    regctl_url="https://github.com/regclient/regclient/releases/latest/download/regctl-linux-${regctl_arch}"
  else
    regctl_url="https://github.com/regclient/regclient/releases/download/${REGCTL_VERSION}/regctl-linux-${regctl_arch}"
  fi

  download_file "$regctl_url" "${DOCKCHECK_WORKDIR}/regctl" && chmod +x "${DOCKCHECK_WORKDIR}/regctl"
}

generate_config() {
  : > "${DOCKCHECK_WORKDIR}/dockcheck.config"

  write_prefixed_config_var AutoMode DOCKCHECK_AUTOMODE
  write_prefixed_config_var AutoPrune DOCKCHECK_AUTOPRUNE
  write_prefixed_config_var AutoSelfUpdate DOCKCHECK_AUTOSELFUPDATE
  write_prefixed_config_var BackupForDays DOCKCHECK_BACKUPFORDAYS
  write_prefixed_config_var BarWidth DOCKCHECK_BARWIDTH
  write_prefixed_config_var CollectorTextFileDirectory DOCKCHECK_COLLECTORTEXTFILEDIRECTORY
  write_prefixed_config_var CurlConnectTimeout DOCKCHECK_CURLCONNECTTIMEOUT
  write_prefixed_config_var CurlRetryCount DOCKCHECK_CURLRETRYCOUNT
  write_prefixed_config_var CurlRetryDelay DOCKCHECK_CURLRETRYDELAY
  write_prefixed_config_var DaysOld DOCKCHECK_DAYSOLD
  write_prefixed_config_var DisplaySourcedFiles DOCKCHECK_DISPLAYSOURCEDFILES
  write_prefixed_config_var DontUpdate DOCKCHECK_DONTUPDATE
  write_prefixed_config_var DRunUp DOCKCHECK_DRUNUP
  write_prefixed_config_var Exclude DOCKCHECK_EXCLUDE
  write_prefixed_config_var ForceRestartStacks DOCKCHECK_FORCERESTARTSTACKS
  write_prefixed_config_var MaxAsync DOCKCHECK_MAXASYNC
  write_prefixed_config_var MonoMode DOCKCHECK_MONOMODE
  write_prefixed_config_var Notify DOCKCHECK_NOTIFY
  write_prefixed_config_var OnlyShowUpdateable DOCKCHECK_ONLYSHOWUPDATEABLE
  write_prefixed_config_var OnlyLabel DOCKCHECK_ONLYLABEL
  write_prefixed_config_var OnlySpecific DOCKCHECK_ONLYSPECIFIC
  write_prefixed_config_var PrintMarkdownURL DOCKCHECK_PRINTMARKDOWNURL
  write_prefixed_config_var PrintReleaseURL DOCKCHECK_PRINTRELEASEURL
  write_prefixed_config_var SkipRecreate DOCKCHECK_SKIPRECREATE
  write_prefixed_config_var Stopped DOCKCHECK_STOPPED
  write_prefixed_config_var Timeout DOCKCHECK_TIMEOUT

  write_prefixed_config_var NOTIFY_CHANNELS DOCKCHECK_NOTIFY_CHANNELS
  write_prefixed_config_var SNOOZE_SECONDS DOCKCHECK_SNOOZE_SECONDS
  write_prefixed_config_var DISABLE_DOCKCHECK_NOTIFICATION DOCKCHECK_DISABLE_DOCKCHECK_NOTIFICATION
  write_prefixed_config_var DISABLE_NOTIFY_NOTIFICATION DOCKCHECK_DISABLE_NOTIFY_NOTIFICATION

  write_prefixed_config_var APPRISE_PAYLOAD DOCKCHECK_APPRISE_PAYLOAD
  write_prefixed_config_var APPRISE_URL DOCKCHECK_APPRISE_URL
  write_prefixed_config_var APPRISE_TAG DOCKCHECK_APPRISE_TAG
  write_prefixed_config_var BARK_KEY DOCKCHECK_BARK_KEY
  write_prefixed_config_var DISCORD_WEBHOOK_URL DOCKCHECK_DISCORD_WEBHOOK_URL
  write_prefixed_config_var DSM_SENDMAILTO DOCKCHECK_DSM_SENDMAILTO
  write_prefixed_config_var DSM_SUBJECTTAG DOCKCHECK_DSM_SUBJECTTAG
  write_prefixed_config_var FILE_PATH DOCKCHECK_FILE_PATH
  write_prefixed_config_var GOTIFY_DOMAIN DOCKCHECK_GOTIFY_DOMAIN
  write_prefixed_config_var GOTIFY_TOKEN DOCKCHECK_GOTIFY_TOKEN
  write_prefixed_config_var HA_ENTITY DOCKCHECK_HA_ENTITY
  write_prefixed_config_var HA_TOKEN DOCKCHECK_HA_TOKEN
  write_prefixed_config_var HA_URL DOCKCHECK_HA_URL
  write_prefixed_config_var MATRIX_ACCESS_TOKEN DOCKCHECK_MATRIX_ACCESS_TOKEN
  write_prefixed_config_var MATRIX_ROOM_ID DOCKCHECK_MATRIX_ROOM_ID
  write_prefixed_config_var MATRIX_SERVER_URL DOCKCHECK_MATRIX_SERVER_URL
  write_prefixed_config_var NTFY_DOMAIN DOCKCHECK_NTFY_DOMAIN
  write_prefixed_config_var NTFY_TOPIC_NAME DOCKCHECK_NTFY_TOPIC_NAME
  write_prefixed_config_var NTFY_AUTH DOCKCHECK_NTFY_AUTH
  write_prefixed_config_var PUSHBULLET_URL DOCKCHECK_PUSHBULLET_URL
  write_prefixed_config_var PUSHBULLET_TOKEN DOCKCHECK_PUSHBULLET_TOKEN
  write_prefixed_config_var PUSHOVER_URL DOCKCHECK_PUSHOVER_URL
  write_prefixed_config_var PUSHOVER_USER_KEY DOCKCHECK_PUSHOVER_USER_KEY
  write_prefixed_config_var PUSHOVER_TOKEN DOCKCHECK_PUSHOVER_TOKEN
  write_prefixed_config_var SLACK_CHANNEL_ID DOCKCHECK_SLACK_CHANNEL_ID
  write_prefixed_config_var SLACK_ACCESS_TOKEN DOCKCHECK_SLACK_ACCESS_TOKEN
  write_prefixed_config_var SMTP_MAIL_FROM DOCKCHECK_SMTP_MAIL_FROM
  write_prefixed_config_var SMTP_MAIL_TO DOCKCHECK_SMTP_MAIL_TO
  write_prefixed_config_var SMTP_SUBJECT_TAG DOCKCHECK_SMTP_SUBJECT_TAG
  write_prefixed_config_var TELEGRAM_CHAT_ID DOCKCHECK_TELEGRAM_CHAT_ID
  write_prefixed_config_var TELEGRAM_TOKEN DOCKCHECK_TELEGRAM_TOKEN
  write_prefixed_config_var TELEGRAM_TOPIC_ID DOCKCHECK_TELEGRAM_TOPIC_ID
  write_prefixed_config_var XMPP_SOURCE_JID DOCKCHECK_XMPP_SOURCE_JID
  write_prefixed_config_var XMPP_SOURCE_PWD DOCKCHECK_XMPP_SOURCE_PWD
  write_prefixed_config_var XMPP_DEST_JID DOCKCHECK_XMPP_DEST_JID

  if [ -n "${DOCKCHECK_CONFIG_APPEND:-}" ]; then
    printf '\n%s\n' "${DOCKCHECK_CONFIG_APPEND}" >> "${DOCKCHECK_WORKDIR}/dockcheck.config"
  fi
}

interval_to_seconds() {
  awk -v interval="${DOCKCHECK_INTERVAL:-24h}" 'BEGIN {
    gsub(",", ".", interval)
    if (interval !~ /^[0-9]+([.][0-9]+)?[hms]?$/) {
      exit 1
    }

    unit = substr(interval, length(interval), 1)
    value = interval
    if (unit ~ /[hms]/) {
      value = substr(interval, 1, length(interval) - 1)
    } else {
      unit = "h"
    }

    if (value <= 0) {
      exit 1
    }
    if (unit == "h") {
      seconds = int((value * 3600) + 0.5)
    } else if (unit == "m") {
      seconds = int((value * 60) + 0.5)
    } else {
      if (value !~ /^[0-9]+$/) {
        exit 1
      }
      seconds = value
    }
    if (seconds < 1) {
      seconds = 1
    }
    print seconds
  }'
}

self_update_container_once() {
  is_true "${DOCKCHECK_CONTAINER_SELFUPDATE:-false}" || return 0

  marker="${DOCKCHECK_WORKDIR}/.container-selfupdate-attempted"
  if [ -e "$marker" ]; then
    log "container self-update already attempted; remove $marker to run again"
    return 0
  fi

  touch "$marker"

  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    log "WARN: docker compose is unavailable; container self-update skipped"
    return 0
  fi

  if [ ! -d "$DOCKCHECK_COMPOSE_DIR" ]; then
    log "WARN: compose directory not found: $DOCKCHECK_COMPOSE_DIR"
    return 0
  fi

  (
    sleep 5
    cd "$DOCKCHECK_COMPOSE_DIR" || exit 0
    compose_args=""
    for file in $(find "$DOCKCHECK_COMPOSE_DIR" -maxdepth 1 -type f \( -name "*.yml" -o -name "*.yaml" \) | LC_ALL=C sort); do
      compose_args="$compose_args -f $file"
    done
    env_arg=""
    [ -f "$DOCKCHECK_COMPOSE_ENV" ] && env_arg="--env-file $DOCKCHECK_COMPOSE_ENV"
    # shellcheck disable=SC2086
    docker compose $env_arg $compose_args up -d --build "$DOCKCHECK_COMPOSE_SERVICE"
  ) &

  log "container self-update scheduled"
}

main() {
  set_default_env
  seed_workdir
  sync_dockcheck_files
  ensure_regctl
  generate_config
  export PATH="${DOCKCHECK_WORKDIR}:${PATH}"

  if [ "$#" -gt 0 ]; then
    log "executing command: $*"
    exec "$@"
  fi

  self_update_container_once

  dockcheck_interval_seconds="$(interval_to_seconds)" || {
    log "invalid DOCKCHECK_INTERVAL: ${DOCKCHECK_INTERVAL:-}"
    exit 1
  }

  if [ "${DOCKCHECK_INITIAL_DELAY_SECONDS:-30}" -gt 0 ]; then
    log "initial delay: ${DOCKCHECK_INITIAL_DELAY_SECONDS}s"
    sleep "$DOCKCHECK_INITIAL_DELAY_SECONDS"
  fi

  while true; do
    log "run started: $(date -Iseconds)"
    log "workdir: ${DOCKCHECK_WORKDIR}"
    log "config: ${DOCKCHECK_WORKDIR}/dockcheck.config"
    if /bin/bash "${DOCKCHECK_WORKDIR}/dockcheck.sh"; then
      log "run finished successfully"
    else
      rc=$?
      log "run failed with rc=${rc}"
    fi
    log "next run in ${DOCKCHECK_INTERVAL:-24h} (${dockcheck_interval_seconds}s)"
    sleep "$dockcheck_interval_seconds"
  done
}

main "$@"
