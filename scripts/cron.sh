#!/bin/bash
MODE="${1:-run}"

MOODLE_ROOT=/var/www/html
CONFIG_FILE="${MOODLE_ROOT}/config.php"

echo "[$(date)] Setting up cron jobs..."

if ! command -v crond &> /dev/null; then
    apk add --no-cache dcron libcap > /dev/null
fi

mkdir -p /var/log /tmp

# ============================================
# Buat lock files dengan ownership www-data
# ============================================
for LOCK in /tmp/moodle-core-cron.lock \
            /tmp/check-preupgrade.lock \
            /tmp/check-plugin-updates.lock; do
    touch "$LOCK"
    chown www-data:www-data "$LOCK"
    chmod 660 "$LOCK"
done

# ============================================
# Buat log files dengan ownership www-data
# ============================================
mkdir -p /var/log
for LOG in /var/log/moodle-cron-core.log \
           /var/log/moodle-backup.log \
           /var/log/moodle-updates.log \
           /var/log/moodle-plugin-updates.log \
           /var/log/moodle-preupgrade.log \
           /var/log/moodle-updates-version.log \
           /var/log/moodle-health.log; do
    touch "$LOG"
    chown www-data:www-data "$LOG"
    chmod 666 "$LOG"
done

# ============================================
# Tunggu config.php ada (max 10 menit)
# ============================================
echo "[$(date)] Menunggu config.php..."
WAIT=0
MAX_WAIT=600
while [ ! -f "$CONFIG_FILE" ]; do
    if [ $WAIT -ge $MAX_WAIT ]; then
        echo "[$(date)] ❌ Timeout menunggu config.php!"
        exit 1
    fi
    sleep 5
    WAIT=$((WAIT + 5))
    echo "[$(date)] ⏳ Menunggu config.php... (${WAIT}s/${MAX_WAIT}s)"
done
echo "[$(date)] ✅ config.php ditemukan!"

if [ "${ENVIRONMENT}" = "development" ]; then
    BACKUP_CRON="0 */6 * * *"
    HEALTH_CRON="*/15 * * * *"
    echo "[$(date)] Cron mode: development"
else
    BACKUP_CRON="0 2 * * *"
    HEALTH_CRON="*/5 * * * *"
    echo "[$(date)] Cron mode: production"
fi

# ============================================
# ✅ FIX: Tulis crontab langsung ke /etc/crontabs/www-data
# Alpine dcron membaca /etc/crontabs/ sebagai root
# ============================================
mkdir -p /etc/crontabs

cat > /etc/crontabs/www-data <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

PGSQL_HOST=${PGSQL_HOST}
PGSQL_USER=${PGSQL_USER}
PGSQL_DATABASE=${PGSQL_DATABASE}
PGSQL_PASSWORD=${PGSQL_PASSWORD}
ENVIRONMENT=${ENVIRONMENT}
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL}

# Moodle core cron (Setiap menit)
* * * * * flock -n /tmp/moodle-core-cron.lock php ${MOODLE_ROOT}/admin/cli/cron.php >> /var/log/moodle-cron-core.log 2>&1

# Scheduled database backup
${BACKUP_CRON} /opt/scripts/backup.sh scheduled >> /var/log/moodle-backup.log 2>&1

# Pre-upgrade detection (Setiap menit)
* * * * * flock -n /tmp/check-preupgrade.lock /opt/scripts/check-preupgrade.sh >> /var/log/moodle-preupgrade.log 2>&1

# Theme/plugin change monitor (Setiap menit)
* * * * * flock -n /tmp/check-plugin-updates.lock /opt/scripts/check-plugin-updates.sh >> /var/log/moodle-plugin-updates.log 2>&1

# Version change monitor (Setiap jam)
0 * * * * /opt/scripts/check-moodle-version.sh >> /var/log/moodle-updates.log 2>&1

# Health check
${HEALTH_CRON} /opt/scripts/health-check.sh >> /var/log/moodle-health.log 2>&1

CRON

chmod 600 /etc/crontabs/www-data
echo "[$(date)] ✅ Cron jobs terdaftar di /etc/crontabs/www-data"

if [ "$MODE" = "run" ]; then
    echo "[$(date)] Starting crond (foreground)..."
    # ✅ FIX: jalankan crond sebagai root agar bisa baca /etc/crontabs/
    exec crond -f -l 2 -L /var/log/crond.log
else
    echo "[$(date)] Setup only, crond tidak dijalankan"
fi