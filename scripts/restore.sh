#!/bin/bash
# Auto restore database & moodle data if database empty


MIGRATION_DIR=/opt/migration

echo "[$(date)] Checking database ..."

export PGPASSWORD="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"

TABLE_COUNT=$(psql -h "${PGSQL_HOST}" \
    -U "${PGSQL_USER}" \
    -d "${PGSQL_DATABASE}" \
    -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" 2>/dev/null | tr -d ' ' )

if [ "$TABLE_COUNT" -gt 0 ] 2>/dev/null; then
    echo "[$(date)] Database has $TABLE_COUNT, Skip restore"
    return 0 2>/dev/null || true
fi

echo "[$(date)] Database is empty, starting restore..."

#restore database

if [ -f "$MIGRATION_DIR/init.sql" ]; then
    echo "[$(date)] Restoring database from init.sql..."
    psql -h "${PGSQL_HOST}" \
         -U "${PGSQL_USER}" \
         -d "${PGSQL_DATABASE}" \
         < "$MIGRATION_DIR/init.sql" 2>&1 | tail -5


    NEW_COUNT=$(psql -h "${PGSQL_HOST}" \
        -U "${PGSQL_USER}" \
        -d "${PGSQL_DATABASE}" \
        -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" 2>/dev/null | tr -d '')

        if [ "$NEW_COUNT" -gt 0 ] 2>/dev/null; then
            echo "[$(date)] Database restored ($NEW_COUNT tables)"
        else
            echo "[$(date)] Database failed to restored"

        fi
else
    echo "[$(date)] init.sql not found, install manually via /install.php"

fi

# Restore moodle data


if [ -f "$MIGRATION_DIR/moodle_data.tar.gz" ]; then
    echo "[$(date)] Restoring moodle_data..."
    tar -xzf "$MIGRATION_DIR/moodle_data.tar.gz" -C "$MOODLE_DATA"
    chown -R www-data:www-data "$MOODLE_DATA"
    echo "[$(date)] Moodle data restored"
else
    echo "[$(date)] moodle_data.tar.gz not found, Moodle will regenerate cache"

fi