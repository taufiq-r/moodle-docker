#!/bin/bash

set -e


# Detect Environment

ENVIRONMENT=${ENVIRONMENT:-production}

#DIR

MOODLE_DIR=/var/www/html #/public
MOODLE_PUBLIC=$MOODLE_DIR/public
MOODLE_DATA=/var/www/moodledata
BACKUP_DIR=$MOODLE_DATA/backups
LOG_FILE=/var/log/moodle-backup.log
UPDATE_LOG=/var/log/moodle-updates.log
SCRIPT_DIR=/opt/scripts

export MOODLE_DIR MOODLE_DATA BACKUP_DIR LOG_FILE UPDATE_LOG ENVIRONMENT SCRIPT_DIR


echo "=== Moodle Startup Script ==="
echo "Environment: $ENVIRONMENT"

#Init logs
mkdir -p /var/log "$BACKUP_DIR"
touch "$LOG_FILE" "$UPDATE_LOG"
chmod 666 "$LOG_FILE" "$UPDATE_LOG"

echo "[$(date)] Log files initialized"


# verify MOodle source
if [ ! -f "$MOODLE_PUBLIC/index.php" ]; then
    echo "[$(date)] FATAL: $MOODLE_PUBLIC/index.php not found. Exiting."
    exit 1
fi

#Generate config.php
if [ -f "$SCRIPT_DIR/generate-config.sh" ]; then
    echo "[$(date)] Running generate-config.sh"
    source "$SCRIPT_DIR/generate-config.sh"
else
    echo "[$(date)] WARNING: generate-config.sh not found"

fi


# Setp directories
mkdir -p "$MOODLE_DATA" "$BACKUP_DIR"
chown -R www-data:www-data "$MOODLE_DIR" "$MOODLE_DATA"
chmod -R 755 "$MOODLE_DIR" "$MOODLE_DATA"

echo "[$(date)] Directories ready"

# Wait for database
echo "[$(date)] Waiting for PostgreSQL..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if pg_isready -h "${PGSQL_HOST}" -U "${PGSQL_USER}" -d "${PGSQL_DATABASE}" > /dev/null 2>&1; then
        echo "[$(date)] PostgreSQL is ready!"
        break
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[$(date)] Waiting for database... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[$(date)] ERROR: Database not reachable"
    exit 1
fi

# Auto restore if database empty
echo ""
echo "[$(date)] Checking if database & moodle data exist.."
if [ "$RESTORE_ON_EMPTY_DB" = "true" ] && [ -f "$SCRIPT_DIR/restore.sh" ]; then
    echo "[$(date)] Running restore.sh (RESTORE_ON_EMPTY_DB=true)"
    source "$SCRIPT_DIR/restore.sh" || true
else
    echo "[$(date)] Restore Skipped"
fi

# Startup backup
if [ -f "$SCRIPT_DIR/backup.sh" ]; then
    echo "[$(date)] Creating startup backup"
    "$SCRIPT_DIR/backup.sh" startup || true
fi
# Setup cron
#source "$SCRIPT_DIR/cron.sh"

# Set permissions
echo "[$(date)] Setting file permissions..."
chown -R www-data:www-data "$MOODLE_DIR" "$MOODLE_DATA"
chmod -R 755 "$MOODLE_DIR" "$MOODLE_DATA"

echo "[$(date)] Permission set completed"

echo "[$(date)] Moodle startup completed!"
echo ""

# Start Service
if  [ "$SERVICE_TYPE" = "php-fpm" ]; then
    echo "[$(date)] Starting Php-Fpm..."
    exec php-fpm

else
    echo "[$(date)] Starting Apache..."
    exec apache2-foreground
fi