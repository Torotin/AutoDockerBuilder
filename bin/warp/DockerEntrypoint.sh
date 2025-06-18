#!/bin/sh
set -e

TEMPLATE="/app/config.json.template"
CONFIG="/etc/warp/config.json"


# Check if the config file exists
if [ ! -f "$CONFIG" ]; then
    # Copy the example config file to the warp directory
    envsubst < "$TEMPLATE" > "$CONFIG"
fi

# Start the warp-plus executable
exec /usr/bin/warp-plus -c "$CONFIG"