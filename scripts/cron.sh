#!/bin/bash
# Setup cron jobs for Moodle
# Moodle 5.1+ structure: CLI tools at MOODLE_ROOT/admin/cli/

MOODLE_ROOT=/var/www/html          # project root — CLI tools (admin/cli/)
MOODLE_PUBLIC=/var/www/html/public # web root    — theme/, plugin/, version.php

# Generate config.php if missing (check at MOODLE_ROOT where symlink is created)
if [ ! -f "$MOODLE_ROOT/config.php" ]; then
    echo "[$(date)] Generating config.php ..."
    /opt/scripts/generate-config.sh
fi

echo "[$(date)] Setting up cron jobs..."

if ! command -v crond &> /dev/null; then
    apk add --no-cache dcron libcap > /dev/null
fi

# Create log files and fix permissions
touch /var/log/moodle-cron-core.log \
      /var/log/moodle-backup.log \
      /var/log/moodle-updates.log \
      /var/log/moodle-updates-version.log \
      /var/log/moodle-plugin-updates.log \
      /var/log/moodle-preupgrade.log

chown www-data:www-data /var/log/moodle-*.log
chmod 666 /var/log/moodle-*.log

crontab -u www-data -r 2>/dev/null || true

if [ "$ENVIRONMENT" = "development" ]; then
    BACKUP_CRON="0 */6 * * *"
    echo "[$(date)] Cron: dev (backup every 6h)"
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
MOODLE_DATABASE_PASSWORD_FILE=${MOODLE_DATABASE_PASSWORD_FILE}

# Moodle core cron — CLI at MOODLE_ROOT/admin/cli/
* * * * * flock -n /tmp/moodle-core-cron.lock php ${MOODLE_ROOT}/admin/cli/cron.php >> /var/log/moodle-cron-core.log 2>&1

# Scheduled database backup
${BACKUP_CRON} /opt/scripts/backup.sh scheduled >> /var/log/moodle-backup.log 2>&1

# Pre-upgrade detection (every minute)
* * * * * flock -n /tmp/check-preupgrade.lock /opt/scripts/check-preupgrade.sh >> /var/log/moodle-preupgrade.log 2>&1

# Theme/plugin change monitor (every minute)
* * * * * flock -n /tmp/check-plugin-updates.lock /opt/scripts/check-plugin-updates.sh >> /var/log/moodle-plugin-updates.log 2>&1

# Version change monitor (every hour)
0 * * * * /opt/scripts/check-moodle-version.sh >> /var/log/moodle-updates-version.log 2>&1

CRON
) | crontab -u www-data -

crond -b 2>&1 || echo "[$(date)] WARNING: crond start failed!"

sleep 2
if pgrep crond > /dev/null; then
    echo "[$(date)] crond running"
else
    echo "[$(date)] WARNING: crond may not be running"
fi