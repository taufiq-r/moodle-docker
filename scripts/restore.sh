#!/bin/bash
# Auto restore database & moodle data if database empty
# Dijalankan di dalam container

# MIGRATION_DIR=/opt/migration
MIGRATION_DIR=${MIGRATION_DIR:-/opt/migration}
MOODLE_DATA=${MOODLE_DATA:-/var/www/moodledata}
LOG_FILE=${LOG_FILE:-/var/log/moodle-backup.log}


echo "[$(date)] Checking database ..." | tee -a "$LOG_FILE"

# export PGPASSWORD="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"
# Ambil password dari env langsung
export PGPASSWORD="${PGSQL_PASSWORD}"

# Cek jumlah tabel Moodle
TABLE_COUNT=$(psql -h "${PGSQL_HOST}" \
    -U "${PGSQL_USER}" \
    -d "${PGSQL_DATABASE}" \
    -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" \
    2>/dev/null | tr -d ' ' )

if [ "$TABLE_COUNT" -gt 0 ] 2>/dev/null; then
    echo "[$(date)] Database has $TABLE_COUNT, Skip restore" | tee -a "$LOG_FILE"
    exit 0
fi

echo "[$(date)] Database is empty, starting restore..." | tee -a "$LOG_FILE"

#restore database

if [ -f "$MIGRATION_DIR/init.sql" ]; then
    echo "[$(date)] Restoring database from init.sql..." | tee -a "$LOG_FILE"
    psql -h "${PGSQL_HOST}" \
         -U "${PGSQL_USER}" \
         -d "${PGSQL_DATABASE}" \
         < "$MIGRATION_DIR/init.sql" 2>&1 | tail -5


    NEW_COUNT=$(psql -h "${PGSQL_HOST}" \
        -U "${PGSQL_USER}" \
        -d "${PGSQL_DATABASE}" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" \
        2>/dev/null | tr -d '')

        if [ "$NEW_COUNT" -gt 0 ] 2>/dev/null; then
            echo "[$(date)] Database restored ($NEW_COUNT tables)" | tee -a "$LOG_FILE"
        else
            echo "[$(date)] Database failed to restored" | tee -a "$LOG_FILE"
            exit 1

        fi
else
    echo "[$(date)] init.sql tidak ditemukan di $MIGRATION_DIR" | tee -a "$LOG_FILE"
    echo "[$(date)] Install manual via browser: /install.php" | tee -a "$LOG_FILE"
fi

# Restore moodle data


if [ -f "$MIGRATION_DIR/moodle_data.tar.gz" ]; then
    echo "[$(date)] Restoring moodle_data..." | tee -a "$LOG_FILE"
    tar -xzf "$MIGRATION_DIR/moodle_data.tar.gz" -C "$MOODLE_DATA"
    chown -R www-data:www-data "$MOODLE_DATA"
    echo "[$(date)] Moodle data restored" | tee -a "$LOG_FILE"
else
    echo "[$(date)] moodle_data.tar.gz not found, Moodle will regenerate cache" | tee -a "$LOG_FILE"

fi