#!/bin/bash
# Backup database & moodledata 


# Load environment dari .env.dev
if [ -f ../.env.dev ]; then
    export $(grep -v '^#' ../.env.dev | xargs)
fi

# Load password dari secrets jika belum ada
export PGPASSWORD="${PGPASSWORD:-$(cat ../secrets/db_password 2>/dev/null)}"



MIGRATION_DIR="../migration"
MOODLE_DATA="${MOODLE_DATA:-/var/www/moodledata}"  #../data/moodle_data-dev}"

mkdir -p "$MIGRATION_DIR"

#backup database ke init.sql
echo "[$(date)] Backup database to $MIGRATION_DIR/init.sql ..."
export PGPASSWORD="${PGPASSWORD:-$(cat /run/secrets/db_password 2>/dev/null)}"
pg_dump -h "${PGSQL_HOST}" \
        -U "${PGSQL_USER}" \
        -d "${PGSQL_DATABASE}" \
        > "$MIGRATION_DIR/init.sql"

if [ $? -eq 0 ]; then
    echo "[$(date)] Database backup finished.."
else
    echo "[$(date)] Database backup failed!"
    exit 1
fi


# Backuo moodledata to moodledata.tar.gz
echo "[$(date)] Starting Backup moodle-data to $MIGRATION_DIR/moodle_data.tar.gz.."
tar -czf "$MIGRATION_DIR/moodle_data.tar.gz" -C "$MOODLE_DATA" .

if [ $? -eq 0 ]; then
    echo "[$(date)] Moodledata backup finished."
else
    echo "[$(date)] Moodledata backup failed!"
    exit 1
fi


