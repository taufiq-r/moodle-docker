#!/bin/bash
# Script for monitor theme/plugin file changes

WATCH_DIR=/var/www/html/public/theme
STATE_FILE=/var/www/moodledata/.last_theme_state
LOG_FILE=${LOG_FILE:-/var/log/moodle-updates.log}


[ ! -d "$WATCH_DIR" ] && { echo "[$(date)] Theme dir not found" >> "$LOG_FILE"; exit 0; }

current_hash=$(find "$WATCH_DIR" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)
[ -z "$current_hash" ] && exit 1

if [ ! -f "$STATE_FILE" ]; then
    echo "$current_hash" > "$STATE_FILE"
    echo "[$(date)] Theme state initialized" >> "$LOG_FILE"
elif [ "$(cat "$STATE_FILE")" != "$current_hash" ]; then
    echo "[$(date)] Theme change detected - creating backup..." >> "$LOG_FILE"
    ./scripts/backup.sh theme-change
    echo "$current_hash" > "$STATE_FILE"

fi