#!/bin/bash

set -e

MOODLE_DIR=/var/www/html
MOODLE_CONFIG=$MOODLE_DIR/config.php
MOODLE_DATA=/var/www/moodledata
BACKUP_DIR=$MOODLE_DATA/backups
LOG_FILE=/var/log/moodle-backup.log
UPDATE_LOG=/var/log/moodle-updates.log

echo "=== Moodle Startup Script ==="

mkdir -p /var/log
touch "$LOG_FILE" "$UPDATE_LOG"
chmod 666 "$LOG_FILE" "$UPDATE_LOG"
echo "[$(date)] Log files initialized"

# Generate config.php jika belum ada

if [ ! -f "$MOODLE_CONFIG" ]; then
  echo "Generating Moodle config.php..."
  DB_PASS="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"

  cat > "$MOODLE_CONFIG" <<EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'pgsql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = getenv('MOODLE_DATABASE_HOST') ?: 'postgres';
\$CFG->dbname    = getenv('MOODLE_DATABASE_NAME') ?: 'moodle';
\$CFG->dbuser    = getenv('MOODLE_DATABASE_USER') ?: 'moodleuser';
\$CFG->dbpass    = '${DB_PASS}';
\$CFG->prefix    = 'mdl_';

\$CFG->wwwroot   = getenv('MOODLE_WWWROOT') ?: 'http://localhost';
\$CFG->dataroot  = '$MOODLE_DATA';
\$CFG->admin     = 'admin';
\$CFG->sslproxy  = false;
\$CFG->directorypermissions = 0777;

// Load default settings jika ada
if (file_exists(__DIR__ . '/../../app/custom/config-defaults.php')) {
    include(__DIR__ . '/../../app/custom/config-defaults.php');
}


require_once(__DIR__ . '/lib/setup.php');
EOF
  chmod 640 "$MOODLE_CONFIG"
  chown www-data:www-data "$MOODLE_CONFIG"
  echo "[$(date)] Moodle config.php created."
else
  echo "[$(date)] Moodle config.php already exists — skipping generation."
fi

mkdir -p /var/www/html/public/theme
chown -R www-data:www-data /var/www/html/public/theme
chmod 755 /var/www/html/public/theme

# Setup backup directory
mkdir -p "$BACKUP_DIR"
chmod 755 "$BACKUP_DIR"
echo "[$(date)] Backup directory created: $BACKUP_DIR"

# Baca DB password dari secret file
DB_PASS="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"
export PGPASSWORD="$DB_PASS"


#4: Wait for database dengan retry logic
echo "[$(date)] Waiting for PostgreSQL to be ready..."
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if pg_isready -h "${MOODLE_DATABASE_HOST}" -U "${MOODLE_DATABASE_USER}" -d "${MOODLE_DATABASE_NAME}" > /dev/null 2>&1; then
        echo "[$(date)] PostgreSQL is ready!" | tee -a "$LOG_FILE"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "[$(date)] Waiting for database... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
    
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[$(date)] ERROR: Database not ready after $MAX_RETRIES attempts" | tee -a "$LOG_FILE"
else
    echo "[$(date)] Creating startup database backup..." | tee -a "$LOG_FILE"
    STARTUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    pg_dump -h "${MOODLE_DATABASE_HOST}" \
            -U "${MOODLE_DATABASE_USER}" \
            -d "${MOODLE_DATABASE_NAME}" \
            > "$BACKUP_DIR/backup_startup_$STARTUP_TIMESTAMP.sql" 2>> "$BACKUP_DIR/backup_error.log"

    if [ -f "$BACKUP_DIR/backup_startup_$STARTUP_TIMESTAMP.sql" ]; then
        BACKUP_SIZE=$(stat -c%s "$BACKUP_DIR/backup_startup_$STARTUP_TIMESTAMP.sql" 2>/dev/null || stat -f%z "$BACKUP_DIR/backup_startup_$STARTUP_TIMESTAMP.sql" 2>/dev/null)
        
        if [ "$BACKUP_SIZE" -gt 100 ]; then
            echo "[$(date)] Startup backup created successfully (size: $BACKUP_SIZE bytes)" | tee -a "$LOG_FILE"
        else
            echo "[$(date)] WARNING: Startup backup is empty (size: $BACKUP_SIZE bytes)" | tee -a "$LOG_FILE"
        fi
    fi
fi

# Create backup script using LOG_FILE

cat > /usr/local/bin/moodle-backup.sh <<'BACKUP_SCRIPT'
#!/bin/bash

BACKUP_DIR=/var/www/moodledata/backups
LOG_FILE=/var/log/moodle-backup.log
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

#timestamp dan better logging
{
    echo "-------------------------------------------"
    echo "[$(date)] Starting database backup..."
    echo "Host: ${MOODLE_DATABASE_HOST}"
    echo "Database: ${MOODLE_DATABASE_NAME}"
    echo "User: ${MOODLE_DATABASE_USER}"
} >> "$LOG_FILE"

export PGPASSWORD="${PGPASSWORD:-$(cat /run/secrets/db_password 2>/dev/null)}"


# Backup error handling
pg_dump -h "${MOODLE_DATABASE_HOST}" \
        -U "${MOODLE_DATABASE_USER}" \
        -d "${MOODLE_DATABASE_NAME}" \
        > "$BACKUP_DIR/backup_$TIMESTAMP.sql" 2>> "$BACKUP_DIR/backup_error.log"

BACKUP_EXIT_CODE=$?

if [ $BACKUP_EXIT_CODE -eq 0 ]; then
    # Check file size sebelum gzip
    BACKUP_SIZE=$(stat -c%s "$BACKUP_DIR/backup_$TIMESTAMP.sql" 2>/dev/null || stat -f%z "$BACKUP_DIR/backup_$TIMESTAMP.sql" 2>/dev/null || echo "0")

    if [ "$BACKUP_SIZE" != "0" ] && [ "$BACKUP_SIZE" != "unknown" ]; then
        gzip "$BACKUP_DIR/backup_$TIMESTAMP.sql"
        echo "[$(date)] Backup completed: backup_$TIMESTAMP.sql.gz (size: $BACKUP_SIZE bytes)" >> "$LOG_FILE"
        
        # keep only last 7 backups
        find "$BACKUP_DIR" -name "backup_*.sql.gz" -mtime +7 -delete
        echo "[$(date)] old backup cleaned (kept last 7 days)" >> "$LOG_FILE"
    else
        echo "[$(date)] ERROR: Backup file too small (size: $BACKUP_SIZE bytes)" >> "$LOG_FILE"
        rm -f "$BACKUP_DIR/backup_$TIMESTAMP.sql"
    fi
else
    echo "[$(date)] ERROR: Backup failed with exit code: $BACKUP_EXIT_CODE" >> "$LOG_FILE"
fi

echo "[$(date)] -------------------------------------------" >> "$LOG_FILE"
BACKUP_SCRIPT

chmod +x /usr/local/bin/moodle-backup.sh

# Create theme/plugin update monitor script

cat > /usr/local/bin/watch-moodle-updates.sh <<'WATCH_SCRIPT'
#!/bin/bash
BACKUP_DIR=/var/www/moodledata/backups
WATCH_DIR=/var/www/html/public/theme
STATE_FILE=/var/www/moodledata/.last_theme_state
LOG_FILE=/var/log/moodle-updates.log

mkdir -p "$BACKUP_DIR"

# Add logging untuk debugging
{
    echo "[$(date)] Checking for theme/plugin updates..."
} >> "$LOG_FILE"

# Calculate hash dari semua file di theme direc
if [ -d "$WATCH_DIR" ]; then
    current_hash=$(find "$WATCH_DIR" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | cut -d' ' -f1)

    if [ -z "$current_hash" ]; then
        echo "[$(date)] ERROR: Could not calculate hash" >> "$LOG_FILE"
        exit 1
    fi
    
    # jika hash berbeda / ada perubahan, maka buat backup
    if [ ! -f "$STATE_FILE" ] ; then
       echo "[$(date)] First run: Creating state file..." >> "$LOG_FILE"
       echo "$current_hash" > "$STATE_FILE"
    elif [ "$(cat "$STATE_FILE" 2>/dev/null)" != "$current_hash" ]; then
        echo "[$(date)] Theme/Plugin update detected! Creating backup..." >> "$LOG_FILE"
        /usr/local/bin/moodle-backup.sh
        echo "$current_hash" > "$STATE_FILE"
        echo "[$(date)] Update backup completed" >> "$LOG_FILE"
    else
        echo "[$(date)] No changes detected" >> "$LOG_FILE"
    fi
else
    echo "[$(date)] WARNING: Theme directory not found: $WATCH_DIR" >> "$LOG_FILE"
fi
WATCH_SCRIPT

chmod +x /usr/local/bin/watch-moodle-updates.sh

# Install dan start cron
echo "[$(date)] Setting up cron jobs..."
apt-get update > /dev/null 2>&1 
apt-get install -y --no-install-recommends cron > /dev/null 2>&1

#clear existing cron jobs untuk www-data
crontab -u www-data -r 2>/dev/null || true

#setup cron job

(crontab -u www-data -l 2>/dev/null || true; \
echo ""; \
echo "SHELL=/bin/bash"; \
echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"; \
echo "MOODLE_DATABASE_HOST=${MOODLE_DATABASE_HOST}"; \
echo "MOODLE_DATABASE_USER=${MOODLE_DATABASE_USER}"; \
echo "MOODLE_DATABASE_NAME=${MOODLE_DATABASE_NAME}"; \
echo "PGPASSWORD=${DB_PASS}"; \
echo ""; \
echo "# Backup database setiap hari jam 2 pagi"; \
echo "0 2 * * * /usr/local/bin/moodle-backup.sh"; \
echo ""; \
echo "# Monitor theme /plugin change every 5 minutes"; \
echo "*/5 * * * * /usr/local/bin/watch-moodle-updates.sh >> /var/log/moodle-updates.log 2>&1") | crontab -u www-data -

echo "[$(date)] Cron jobs installed."

# Show cron jobs for verification
crontab -u www-data -l 2>/dev/null || echo "No cron jobs"

# start cronjob service

service cron start 2>&1 || echo "[$(date)] WARNING: Cron start had issues"
echo "[$(date)] Cron service started"

# Verify cron service is running
sleep 2
if pgrep cron  > /dev/null; then
    echo "[$(date)] Cron service is running"
else
    echo "[$(date)] WARNING: Cron service may not be running properly"
fi

# set permissions
echo "[$(date)] Setting file permission..."
chown -R www-data:www-data /var/www/html
chown -R www-data:www-data /var/www/moodledata
chown www-data:www-data "$LOG_FILE"
chown www-data:www-data "$UPDATE_LOG"

chmod -R 755 /var/www/html # 7 = rwx, 5 = r-x / rwxr-xr-x
chmod -R 755 /var/www/moodledata # rwxr-xr-x
chmod 666 "$LOG_FILE"
chmod 666 "$UPDATE_LOG"


echo "[$(date)] Moodle startup completed, starting Apache ..."
echo ""


exec apache2-foreground