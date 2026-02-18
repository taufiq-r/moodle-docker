#!/bin/bash
#Script to setup cron jobs

# Inisialisasi config.php jika belum ada
if [ ! -f /var/www/html/config.php ]; then
    echo "[$(date)] Generating config.php ..."
    /scripts/generate-config.sh
fi


echo "[$(date)] Setting up cron jobs..."

if ! command -v crond &> /dev/null; then
    apk add --no-cache dcron libcap > /dev/null
fi

crontab -u www-data -r 2>/dev/null || true

if [ "$ENVIRONMENT" = "development" ]; then
    BACKUP_CRON="0 */6 * * *"
    echo "[$(date)]  Cron: dev (backup every 6h)"

else
    BACKUP_CRON="0 2 * * *"
    echo "[$(date)] Cron: prod (backup daily at 2am)"
fi

(cat <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PGSQL_HOST=${PGSQL_HOST}
PGSQL_USER=${PGSQL_USER}
PGSQL_DATABASE=${PGSQL_DATABASE}
PGPASSWORD=${PGPASSWORD}

#database backup
${BACKUP_CRON} opt/scripts/backup.sh scheduled >> /var/log/moodle-backup.log 2>&1

#theme/plugin monitor (5min)
*/5 * * * * opt/scripts/watch-moodle-updates.sh  >> /var/log/moodle-updates.log 2>&1

# Version check (every hour)
0 * * * * opt/scripts/check-moodle-version.sh >> /var/log/moodle-updates-version.log 2>&1
CRON
) | crontab -u www-data -

crond -b 2>&1 || echo "[$(date)] WARNING: Cront start failed!"


sleep 2
if pgrep crond > /dev/null; then
    echo "[$(date)] Cron running"
else
    echo "[$(date)] Cron may not running"
fi
