#!/bin/bash
# Script to monitor m00dle Version change

VERSION_FILE=/var/www/html/public/version.php
STATE_FILE=/var/www/moodledata/.last_version
LOG_FILE=${LOG_FILE:-/var/log/moodle-updates-version.log}

[ ! -f "$VERSION_FILE" ] && { echo "[$(date)] version.php not found}" >> "$LOG_FILE"; exit 0; }

CURRENT_VERSION=$(grep -oP "^\\\$release\s*=\s*['\"]?\K[^'\"]*" "$VERSION_FILE" 2>/dev/null | head -1)

[ -z "$CURRENT_VERSION" ] && CURRENT_VERSION=$(grep -oP "^\\\$version\s*=\s*\K\d+\.\d+" "$VERSION_FILE" 2>/dev/null | head -1)
[ -z "$CURRENT_VERSION" ] && exit 1

LAST_VERSION=$(cat "$STATE_FILE" 2>/dev/null || echo "")

if [ "$CURRENT_VERSION" != "$LAST_VERSION" ]; then
    if [ -n "$LAST_VERSION" ]; then
        echo "[$(date)] Version changed: $LAST_VERSION -> $CURRENT_VERSION" >> "$LOG_FILE"
        opt/scripts/backup.sh "upgrade_${LAST_VERSION}_to_${CURRENT_VERSION}"

    else
        echo "[$(date)] Initial version: $CURRENT_VERSION" >> "$LOG_FILE"
    fi
    echo "$CURRENT_VERSION" > "$STATE_FILE"
fi


