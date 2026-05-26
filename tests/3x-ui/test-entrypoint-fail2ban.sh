#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/bin/3x-ui/DockerEntrypoint.sh"
ALPINE_IMAGE="${ALPINE_IMAGE:-alpine:3.22}"

run_container() {
    docker run --rm -i \
        -v "${SCRIPT}:/fixture/DockerEntrypoint.sh:ro" \
        "${ALPINE_IMAGE}" sh -s
}

test_enabled_creates_upstream_3x_ipl_rules() {
    run_container <<'CONTAINER'
set -eu
apk add --no-cache bash >/dev/null
sed 's/\r$//' /fixture/DockerEntrypoint.sh > /tmp/DockerEntrypoint.sh
mkdir -p /app /stub /state
cat > /app/x-ui <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /stub/sleep <<'EOF'
#!/bin/sh
:
EOF
cat > /stub/fail2ban-client <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > /state/fail2ban.args
EOF
chmod +x /app/x-ui /stub/sleep /stub/fail2ban-client

PATH="/stub:${PATH}" XUI_ENABLE_FAIL2BAN=true XUI_LOG_FOLDER=/state/logs \
    bash /tmp/DockerEntrypoint.sh

grep -Fqx -- '-x start' /state/fail2ban.args
test -f /state/logs/3xipl.log
test -f /state/logs/3xipl-banned.log
grep -Fqx -- 'logpath=/state/logs/3xipl.log' /etc/fail2ban/jail.d/3x-ipl.conf
grep -Fq -- '\[LIMIT_IP\]' /etc/fail2ban/filter.d/3x-ipl.conf
grep -Fq -- 'actionstart = <iptables> -N f2b-<name>' /etc/fail2ban/action.d/3x-ipl.conf
grep -Fq -- 'actionban = <iptables> -I f2b-<name> 1 -s <ip> -j <blocktype>' /etc/fail2ban/action.d/3x-ipl.conf
grep -Fq -- 'actionunban = <iptables> -D f2b-<name> -s <ip> -j <blocktype>' /etc/fail2ban/action.d/3x-ipl.conf
grep -Fq -- '/state/logs/3xipl-banned.log' /etc/fail2ban/action.d/3x-ipl.conf
CONTAINER
}

test_disabled_skips_rules_and_client() {
    run_container <<'CONTAINER'
set -eu
apk add --no-cache bash >/dev/null
sed 's/\r$//' /fixture/DockerEntrypoint.sh > /tmp/DockerEntrypoint.sh
mkdir -p /app /stub /state
cat > /app/x-ui <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /stub/sleep <<'EOF'
#!/bin/sh
:
EOF
cat > /stub/fail2ban-client <<'EOF'
#!/bin/sh
touch /state/fail2ban-called
EOF
chmod +x /app/x-ui /stub/sleep /stub/fail2ban-client

PATH="/stub:${PATH}" XUI_ENABLE_FAIL2BAN=false XUI_LOG_FOLDER=/state/logs \
    bash /tmp/DockerEntrypoint.sh

test ! -e /state/fail2ban-called
test ! -e /state/logs/3xipl.log
test ! -e /etc/fail2ban/jail.d/3x-ipl.conf
CONTAINER
}

test_failed_client_fails_startup_with_diagnostic() {
    run_container <<'CONTAINER'
set -eu
apk add --no-cache bash >/dev/null
sed 's/\r$//' /fixture/DockerEntrypoint.sh > /tmp/DockerEntrypoint.sh
mkdir -p /app /stub /state
cat > /app/x-ui <<'EOF'
#!/bin/sh
exit 0
EOF
cat > /stub/sleep <<'EOF'
#!/bin/sh
:
EOF
cat > /stub/fail2ban-client <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x /app/x-ui /stub/sleep /stub/fail2ban-client

if output="$(PATH="/stub:${PATH}" XUI_ENABLE_FAIL2BAN=true XUI_LOG_FOLDER=/state/logs \
    bash /tmp/DockerEntrypoint.sh 2>&1)"; then
    printf 'entrypoint unexpectedly accepted fail2ban startup failure\n' >&2
    exit 1
fi
printf '%s\n' "$output" | grep -Fq -- 'Fail2Ban failed to start.'
CONTAINER
}

test_enabled_creates_upstream_3x_ipl_rules
test_disabled_skips_rules_and_client
test_failed_client_fails_startup_with_diagnostic
printf 'PASS: 3x-ui fail2ban entrypoint behavior\n'
