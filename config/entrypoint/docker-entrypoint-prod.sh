#!/bin/bash
set -e

echo "========================================"
echo "   Moodle Production Container"
echo "========================================"

MOODLE_DIR=/var/www/html
MOODLE_DATA=/var/www/moodledata
CONFIG_BACKUP="${MOODLE_DATA}/config.php.bak"

# ============================================
# Validasi environment variables wajib
# ============================================
REQUIRED_VARS="PGSQL_HOST PGSQL_USER PGSQL_DATABASE PGSQL_PASSWORD"
for VAR in $REQUIRED_VARS; do
    if [ -z "${!VAR}" ]; then
        echo "[PROD] ERROR: Environment variable '$VAR' tidak boleh kosong"
        exit 1
    fi
done

# MOODLE_WWWROOT hanya wajib untuk web container (bukan cron)
if [ $# -eq 0 ] && [ -z "${MOODLE_WWWROOT}" ]; then
    echo "[PROD] ERROR: Environment variable 'MOODLE_WWWROOT' tidak boleh kosong"
    exit 1
fi

# ============================================
# Setup directories
# ============================================
echo "[PROD] Setting up directories..."
mkdir -p "$MOODLE_DATA" \
         "$MOODLE_DATA/backups" \
         /var/log

touch /var/log/moodle-backup.log \
      /var/log/moodle-cron-core.log \
      /var/log/moodle-preupgrade.log \
      /var/log/moodle-plugin-updates.log \
      /var/log/moodle-updates.log

chmod 666 /var/log/moodle-*.log
chown -R www-data:www-data "$MOODLE_DATA"
chmod 750 "$MOODLE_DATA"

# ============================================
# Fix permission agar installer bisa tulis config.php
# ============================================
echo "[PROD] Fixing write permission..."
chown -R www-data:www-data "$MOODLE_DIR"

# ============================================
# Restore config.php dari backup jika ada
# ============================================
if [ ! -f "$MOODLE_DIR/config.php" ] && [ -f "$CONFIG_BACKUP" ]; then
    echo "[PROD] ♻️  Restoring config.php dari backup..."
    cp "$CONFIG_BACKUP" "$MOODLE_DIR/config.php"
    chown www-data:www-data "$MOODLE_DIR/config.php"
    echo "[PROD] ✅ config.php restored!"
fi

# ============================================
# Buat symlink public/config.php (Moodle 5.x)
# ============================================
_setup_config_symlink() {
    # Hapus jika ada file biasa (bukan symlink) di public/config.php
    if [ -f "$MOODLE_DIR/public/config.php" ] && [ ! -L "$MOODLE_DIR/public/config.php" ]; then
        echo "[PROD] ⚠️  public/config.php adalah file biasa, menghapus..."
        rm -f "$MOODLE_DIR/public/config.php"
    fi

    if [ -f "$MOODLE_DIR/config.php" ] && [ ! -e "$MOODLE_DIR/public/config.php" ]; then
        echo "[PROD] 🔗 Membuat symlink public/config.php → ../config.php"
        ln -sf "$MOODLE_DIR/config.php" "$MOODLE_DIR/public/config.php"
        echo "[PROD] ✅ Symlink dibuat!"
    fi
}

# ============================================
# Cek config.php
# ============================================
if [ ! -f "$MOODLE_DIR/config.php" ]; then
    echo ""
    echo "  ⚠️  config.php TIDAK ditemukan (fresh install)"
    echo "  ✅ Buka browser: ${MOODLE_WWWROOT}/install.php"
    echo "  📋 Gunakan settings berikut saat instalasi:"
    echo "     - Database host   : ${PGSQL_HOST}"
    echo "     - Database name   : ${PGSQL_DATABASE}"
    echo "     - Database user   : ${PGSQL_USER}"
    echo "     - Data directory  : ${MOODLE_DATA}"
    echo "     - Moodle wwwroot  : ${MOODLE_WWWROOT}"
    echo ""
    echo "  💾 config.php akan otomatis di-backup ke moodledata"
    echo ""

    # Watcher: tunggu config.php terbuat lalu backup + symlink
    (
        echo "[PROD] 👀 Watching untuk config.php..."
        WATCH_RETRIES=600
        WATCHED=0
        while [ $WATCHED -lt $WATCH_RETRIES ]; do
            sleep 1
            if [ -f "$MOODLE_DIR/config.php" ]; then
                echo "[PROD] ✅ config.php terdeteksi! Menyimpan backup..."
                cp "$MOODLE_DIR/config.php" "$CONFIG_BACKUP"
                chmod 640 "$CONFIG_BACKUP"
                echo "[PROD] ✅ Backup tersimpan di: $CONFIG_BACKUP"
                _setup_config_symlink
                echo "[PROD] 💡 Instalasi selesai, Moodle siap digunakan!"
                break
            fi
            WATCHED=$((WATCHED + 1))
        done
        if [ $WATCHED -eq $WATCH_RETRIES ]; then
            echo "[PROD] ⚠️  Timeout: config.php tidak ditemukan setelah 10 menit"
        fi
    ) &

else
    echo "[PROD] ✅ config.php ditemukan"

    # Backup config.php jika belum ada
    if [ ! -f "$CONFIG_BACKUP" ]; then
        cp "$MOODLE_DIR/config.php" "$CONFIG_BACKUP"
        echo "[PROD] 💾 config.php di-backup ke $CONFIG_BACKUP"
    fi

    # Tunggu PostgreSQL
    echo "[PROD] Menunggu PostgreSQL..."
    MAX_RETRIES=30
    RETRY=0
    until pg_isready -h "${PGSQL_HOST}" -U "${PGSQL_USER}" -d "${PGSQL_DATABASE}" > /dev/null 2>&1; do
        RETRY=$((RETRY + 1))
        if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
            echo "[PROD] ERROR: PostgreSQL tidak tersedia setelah ${MAX_RETRIES} percobaan"
            exit 1
        fi
        echo "[PROD] Menunggu postgres... ($RETRY/$MAX_RETRIES)"
        sleep 3
    done
    echo "[PROD] ✅ PostgreSQL siap!"

    # Auto restore jika database kosong
    if [ "${RESTORE_ON_EMPTY_DB}" = "true" ]; then
        echo "[PROD] Checking database untuk auto-restore..."
        /opt/scripts/restore.sh || true
    fi
fi

# ============================================
# Setup cron jobs
# ============================================
if [ $# -eq 0 ]; then
    echo "[PROD] Setting up cron..."
    /opt/scripts/cron.sh setup
fi

echo "[PROD] ✅ Container siap!"
echo "========================================"
echo ""

if [ $# -eq 0 ]; then
    exec php-fpm
else
    exec "$@"
fi