#!/bin/bash
# Backup database & moodledata 

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MIGRATION_DIR="$PROJECT_DIR/migration"

# ============================================
# Tentukan environment (dev/prod)
# ============================================
ENV_MODE="${1:-dev}"

if [ "$ENV_MODE" = "prod" ]; then
    ENV_FILE="$PROJECT_DIR/.env.prod"
    DB_CONTAINER="moodle-pgdb-prod"
    APP_CONTAINER="moodle-web-prod"
else
    ENV_FILE="$PROJECT_DIR/.env.dev"
    DB_CONTAINER="moodle-pgdb-dev"
    APP_CONTAINER="moodle-web-dev"
fi

# # Load environment dari .env.dev
# if [ -f ../.env.dev ]; then
#     export $(grep -v '^#' ../.env.dev | xargs)
# fi

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
    echo "✅ Loaded env dari $ENV_FILE"
else
    echo "❌ File $ENV_FILE tidak ditemukan"
    exit 1
fi



# # Load password dari secrets jika belum ada
# export PGPASSWORD="${PGPASSWORD:-$(cat ../secrets/db_password 2>/dev/null)}"

mkdir -p "$MIGRATION_DIR"

# MIGRATION_DIR="../migration"
# MOODLE_DATA="${MOODLE_DATA:-/var/www/moodledata}"  #../data/moodle_data-dev}"

# mkdir -p "$MIGRATION_DIR"

echo "========================================"
echo "  Moodle Migration Backup"
echo "========================================"
echo "Database : ${PGSQL_DATABASE}"
echo "Host     : ${PGSQL_HOST}"
echo "Output   : $MIGRATION_DIR"
echo ""

#backup database ke init.sql
echo "[$(date)] Backup database to $MIGRATION_DIR/init.sql ..."


# export PGPASSWORD="${PGPASSWORD:-$(cat /run/secrets/db_password 2>/dev/null)}"
docker exec moodle-pgdb-dev \
    pg_dump \
    -U "${PGSQL_USER}" \
    -d "${PGSQL_DATABASE}" \
    > "$MIGRATION_DIR/init.sql"


# pg_dump -h "${PGSQL_HOST}" \
#         -U "${PGSQL_USER}" \
#         -d "${PGSQL_DATABASE}" \
#         > "$MIGRATION_DIR/init.sql"

if [ $? -eq 0 ]; then
    echo "[$(date)] Database backup finished.."
else
    echo "[$(date)] Database backup failed!"
    exit 1
fi


# ============================================
# Backup moodledata via container
# ============================================

echo "[$(date)] Starting Backup moodle-data to $MIGRATION_DIR/moodle_data.tar.gz.."
# tar -czf "$MIGRATION_DIR/moodle_data.tar.gz" -C "$MOODLE_DATA" .

docker exec moodle-web-dev \
    tar -czf - -C /var/www/moodledata . \
    > "$MIGRATION_DIR/moodle_data.tar.gz"

if [ $? -eq 0 ]; then
    echo "[$(date)] Moodledata backup finished."
else
    echo "[$(date)] Moodledata backup failed!"
    exit 1
fi

echo ""
echo "========================================"
echo "  Backup selesai!"
echo "  - $MIGRATION_DIR/init.sql"
echo "  - $MIGRATION_DIR/moodle_data.tar.gz"
echo ""
echo "  Jalankan di server tujuan:"
echo "  RESTORE_ON_EMPTY_DB=true di .env"
echo "========================================"


