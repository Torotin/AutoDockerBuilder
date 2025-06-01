#!/bin/bash
set -euo pipefail

# === Logging Setup (define first!) ===
RED='\e[31m'; GREEN='\e[32m'; YELLOW='\e[33m'; BLUE='\e[34m'; NC='\e[0m'
log() {
    local level="$1" timestamp msg
    shift
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    msg="$*"
    case "$level" in
        INFO) echo -e "${GREEN}[INFO] [$timestamp] $msg${NC}" ;;
        ERROR) echo -e "${YELLOW}[ERROR] [$timestamp] $msg${NC}" >&2 ;;
        DEBUG) [[ "${DEBUG:-false}" == "true" ]] && echo -e "${BLUE}[DEBUG] [$timestamp] $msg${NC}" ;;
        FATAL) echo -e "${RED}[FATAL] [$timestamp] $msg${NC}" >&2; exit 1 ;;
        *) echo -e "${YELLOW}[UNKNOWN] [$timestamp] $msg${NC}" ;;
    esac
}

# === Global Config ===
XUIDB="/etc/x-ui/x-ui.db"
ARCH=$(uname -m)
ENV_FILE="/app/.env"

# === Load .env if exists ===
if [ -f "$ENV_FILE" ]; then
    log "INFO" "Loading environment variables from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
else
    log "INFO" "No .env file found. Using current environment variables."
fi

# === Utility ===
generate_random_string() {
    head -c 100 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$1"
}

install_package_if_missing() {
    local alias="$1" pkg="$2"
    if ! command -v "$alias" &>/dev/null; then
        log "INFO" "Installing package: $pkg"
        apk add --no-cache "$pkg" &>/dev/null || log "FATAL" "Failed to install $pkg"
    fi
}

get_xray_binary_path() {
    case "$ARCH" in
        x86_64) XRAY="xray-linux-amd64" ;;
        aarch64) XRAY="xray-linux-arm64" ;;
        armv7l) XRAY="xray-linux-armv7" ;;
        i386) XRAY="xray-linux-386" ;;
        *) log "FATAL" "Unknown architecture: $ARCH" ;;
    esac
    XRAY_PATH="/app/bin/$XRAY"
    [[ -x "$XRAY_PATH" ]] || chmod +x "$XRAY_PATH"
    echo "$XRAY_PATH"
}

# === SQLite ===
SQLite_execute() {
    echo -e "BEGIN TRANSACTION;\n$1\nCOMMIT;" | sqlite3 -batch "$XUIDB" && log "INFO" "$2" || log "FATAL" "$3"
}

SQLite_update_data() {
    sqlite3 -batch "$1" "UPDATE $2 SET $3 WHERE $4;" || log "FATAL" "Failed to update $2"
    log "INFO" "Updated $2 successfully"
}

SQLite_query_data() {
    local result
    result=$(sqlite3 -batch "$1" "$2" 2>&1) || log "FATAL" "SQLite error: $result"
    echo "$result"
}

# === Admin Credentials ===
update_user_and_password() {
    local current_user current_pass
    current_user=$(SQLite_query_data "$XUIDB" "SELECT username FROM users WHERE id=1;")
    current_pass=$(SQLite_query_data "$XUIDB" "SELECT password FROM users WHERE id=1;")

    new_admin="${panel_admin:-}"
    new_admin_password="${panel_admin_password:-}"

    if [[ "$current_user" == "admin" || "$current_pass" == "admin" || -z "$new_admin" || -z "$new_admin_password" ]]; then
        new_admin=$(generate_random_string $((16 + RANDOM % 17)))
        new_admin_password=$(generate_random_string $((16 + RANDOM % 17)))
        log "DEBUG" "Generated new admin credentials"
    fi

    export new_admin new_admin_password

    if [[ "$current_user" == "$new_admin" && "$current_pass" == "$new_admin_password" ]]; then
        log "INFO" "Admin credentials unchanged"
        return
    fi

    SQLite_update_data "$XUIDB" "users" "username='$new_admin', password='$new_admin_password'" "id=1"
}

# === Settings Update ===
update_settings_table() {
    log "INFO" "Updating settings table..."
    local updated=0 skipped=0 sql_batch=""

    while IFS=: read -r key value; do
        [[ -z "$value" ]] && log "DEBUG" "Skipping '$key' (empty value)" && continue
        current=$(sqlite3 "$XUIDB" "SELECT value FROM settings WHERE key='$key';")
        if [[ "$current" != "$value" ]]; then
            sql_batch+="DELETE FROM settings WHERE key='$key';"
            sql_batch+="INSERT INTO settings (key,value) VALUES ('$key','$value');"
            ((updated++))
        else
            ((skipped++))
        fi
    done <<< "$SETTINGS"

    [[ -n "$sql_batch" ]] && SQLite_execute "$sql_batch" "$updated settings updated" "Failed to update settings"
    log "INFO" "Skipped: $skipped"
}

# === Reality Key Generation ===
UPDATE_XUIDB() {
    log "INFO" "Generating Xray Reality keys..."
    TMPFILE=$(mktemp)
    $XRAY_BINARY x25519 > "$TMPFILE"
    private_key=$(awk '/Private key:/ {print $3}' "$TMPFILE")
    public_key=$(awk '/Public key:/ {print $3}' "$TMPFILE")
    rm -f "$TMPFILE"

    client_id=$($XRAY_BINARY uuid)
    [[ -z "$private_key" || -z "$public_key" || -z "$client_id" ]] && log "FATAL" "Failed to generate keys or UUID"

    export private_key public_key client_id
    log "DEBUG" "Private: $private_key | Public: $public_key | UUID: $client_id"
}

# === Settings KVP block ===
SETTINGS=$(cat <<EOF
webListen:${webListen}
webDomain:${webDomain}
webPort:${webPort}
webCertFile:${webCertFile}
webKeyFile:${webKeyFile}
webBasePath:${webBasePath}
sessionMaxAge:${sessionMaxAge}
pageSize:${pageSize}
expireDiff:${expireDiff}
trafficDiff:${trafficDiff}
remarkModel:${remarkModel}
tgBotEnable:${tgBotEnable}
tgBotToken:${tgBotToken}
tgBotProxy:${tgBotProxy}
tgBotAPIServer:${tgBotAPIServer}
tgBotChatId:${tgBotChatId}
tgRunTime:${tgRunTime}
tgBotBackup:${tgBotBackup}
tgBotLoginNotify:${tgBotLoginNotify}
tgCpu:${tgCpu}
tgLang:${tgLang}
timeLocation:${TZ}
secretEnable:false
subEnable:${subEnable}
subListen:${subListen}
subPort:${subPort}
subPath:${subPath}
subDomain:${subDomain}
subCertFile:${subCertFile}
subKeyFile:${subKeyFile}
subUpdates:${subUpdates}
externalTrafficInformEnable:${externalTrafficInformEnable}
externalTrafficInformURI:${externalTrafficInformURI}
subEncrypt:${subEncrypt}
subShowInfo:${subShowInfo}
subURI:${subURI}
subJsonURI:${subJsonURI}
subJsonPath:${subJsonPath}
subJsonFragment:${subJsonFragment}
subJsonNoises:${subJsonNoises}
subJsonMux:${subJsonMux}
subJsonRules:${subJsonRules}
datepicker:${datepicker}
EOF
)

# === DB File Waiter ===
if [ ! -f "$XUIDB" ]; then
    log "ERROR" "x-ui.db not found. Waiting up to 60s..."
    for i in {1..12}; do
        sleep 5
        [[ -f "$XUIDB" ]] && log "INFO" "Found $XUIDB. Rebooting..." && sleep 5 && reboot
    done
    log "FATAL" "x-ui.db not found after timeout."
fi

# === Main Execution ===
export XRAY_BINARY=$(get_xray_binary_path)
log "DEBUG" "Using binary: $XRAY_BINARY"

install_package_if_missing "sqlite3" "sqlite"
install_package_if_missing "openssl" "openssl"
install_package_if_missing "jq" "jq"

update_user_and_password
update_settings_table
UPDATE_XUIDB

log "INFO" "Script completed successfully!"
log "INFO" "Panel URL: https://${webDomain}${webBasePath}"
log "INFO" "Username: $new_admin"
log "INFO" "Password: $new_admin_password"
