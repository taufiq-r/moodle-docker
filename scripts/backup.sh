#!/bin/bash
# Moodle database backup script

BACKUP_DIR=${BACKUP_DIR:-/var/www/moodledata/backups}
LOG_FILE=${LOG_FILE:-/var/log/moodle-backup.log}
BACKUP_TYPE=${1:-scheduled}
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"
# export PGPASSWORD="${PGPASSWORD:-$(cat /run/secrets/db_password 2>/dev/null)}"
export PGPASSWORD="${PGSQL_PASSWORD}"

# echo "[$(date)] Starting ${BACKUP_TYPE} backup ..." >> "$LOG_FILE"
echo "[$(date)] Starting ${BACKUP_TYPE} backup..." | tee -a "$LOG_FILE"


BACKUP_FILE="$BACKUP_DIR/backup_${BACKUP_TYPE}_${TIMESTAMP}.sql"

pg_dump -h "${PGSQL_HOST}" \
        -U "${PGSQL_USER}" \
        -d "${PGSQL_DATABASE}" \
        > "$BACKUP_FILE" 2>> "$BACKUP_DIR/backups_error.log"

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || echo "0")

    if [ "$BACKUP_SIZE" -gt 100 ]; then
        gzip "$BACKUP_FILE"
        echo "[$(date)] Backup: $(basename $BACKUP_FILE).gz ($BACKUP_SIZE bytes)" | tee -a "$LOG_FILE"

        # Keep last 7 days only
        find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete
        echo "[$(date)] Old backups cleaned" >> "$LOG_FILE"
        #find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete

    else 
        echo "[$(date)] Backup too small ($BACKUP_SIZE bytes), removed" | tee -a "$LOG_FILE"
        rm -f "$BACKUP_FILE"
        exit 1
    fi
else
    echo "[$(date)] Backup failed" | tee -a "$LOG_FILE"
    rm -f "$BACKUP_FILE"
    exit 1
fi
