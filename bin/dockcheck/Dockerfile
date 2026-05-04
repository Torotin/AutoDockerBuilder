FROM alpine:3.20

ARG DOCKCHECK_REF=main
ARG DOCKCHECK_RAW_URL=https://raw.githubusercontent.com/mag37/dockcheck/${DOCKCHECK_REF}

ENV PATH="/opt/apprise/bin:${PATH}"

RUN set -eux; \
    apk add --no-cache \
      bash \
      ca-certificates \
      coreutils \
      curl \
      docker-cli \
      docker-cli-compose \
      findutils \
      jq \
      msmtp \
      python3 \
      py3-pip \
      tzdata; \
    apk add --no-cache go-sendxmpp || true; \
    python3 -m venv /opt/apprise; \
    /opt/apprise/bin/pip install --no-cache-dir --upgrade pip apprise; \
    mkdir -p /usr/local/share/dockcheck-seed/notify_templates /usr/local/share/dockcheck-seed/addons/prometheus

RUN set -eux; \
    curl -fsSL "${DOCKCHECK_RAW_URL}/dockcheck.sh" -o /usr/local/share/dockcheck-seed/dockcheck.sh; \
    curl -fsSL "${DOCKCHECK_RAW_URL}/default.config" -o /usr/local/share/dockcheck-seed/default.config; \
    curl -fsSL "${DOCKCHECK_RAW_URL}/addons/prometheus/prometheus_collector.sh" -o /usr/local/share/dockcheck-seed/addons/prometheus/prometheus_collector.sh; \
    for file in \
      notify_DSM.sh \
      notify_HA.sh \
      notify_apprise.sh \
      notify_bark.sh \
      notify_discord.sh \
      notify_file.sh \
      notify_generic.sh \
      notify_gotify.sh \
      notify_matrix.sh \
      notify_ntfy.sh \
      notify_pushbullet.sh \
      notify_pushover.sh \
      notify_slack.sh \
      notify_smtp.sh \
      notify_telegram.sh \
      notify_v2.sh \
      notify_xmpp.sh \
      urls.list; do \
        curl -fsSL "${DOCKCHECK_RAW_URL}/notify_templates/${file}" -o "/usr/local/share/dockcheck-seed/notify_templates/${file}"; \
      done; \
    cp /usr/local/share/dockcheck-seed/notify_templates/urls.list /usr/local/share/dockcheck-seed/urls.list; \
    chmod +x /usr/local/share/dockcheck-seed/dockcheck.sh /usr/local/share/dockcheck-seed/notify_templates/*.sh /usr/local/share/dockcheck-seed/addons/prometheus/prometheus_collector.sh

COPY entrypoint.sh /usr/local/bin/dockcheck-entrypoint
RUN chmod +x /usr/local/bin/dockcheck-entrypoint

WORKDIR /_dockcheck
ENTRYPOINT ["/usr/local/bin/dockcheck-entrypoint"]
