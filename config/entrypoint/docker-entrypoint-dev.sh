#!/bin/bash
set -e

echo "========================================"
echo "   Moodle Development Container"
echo "========================================"

MOODLE_DIR=/var/www/html
MOODLE_DATA=/var/www/moodledata
CONFIG_BACKUP=${MOODLE_DATA}/config.php.bak

# ============================================
# Validasi environment variables
# ============================================
REQUIRED_VARS="PGSQL_HOST PGSQL_USER PGSQL_DATABASE PGSQL_PASSWORD"
for VAR in $REQUIRED_VARS; do
    if [ -z "${!VAR}" ]; then
        echo "[DEV] ERROR: Environment variable '$VAR' tidak boleh kosong"
        exit 1
    fi
done

# ============================================
# Setup moodledata
# ============================================
echo "[DEV] Setting up moodledata..."
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
chmod 777 "$MOODLE_DATA"

# ============================================
# Fix permission agar installer bisa tulis config.php
# ============================================
echo "[DEV] Fixing write permission for Moodle installer..."
chown -R www-data:www-data "$MOODLE_DIR"

# ============================================
# Restore config.php dari backup jika ada
# ============================================
if [ ! -f "$MOODLE_DIR/config.php" ] && [ -f "$CONFIG_BACKUP" ]; then
    echo "[DEV] Restoring config.php dari backup..."
    cp "$CONFIG_BACKUP" "$MOODLE_DIR/config.php"
    chown www-data:www-data "$MOODLE_DIR/config.php"
    echo "[DEV] ✅ config.php restored!"
fi

# ============================================
# Buat symlink public/config.php (Moodle 5.x)
# ============================================
_setup_config_symlink() {
    # Hapus jika ada file biasa (bukan symlink) di public/config.php
    if [ -f "$MOODLE_DIR/public/config.php" ] && [ ! -L "$MOODLE_DIR/public/config.php" ]; then
        echo "[DEV] ⚠️  public/config.php adalah file biasa, memindahkan ke root..."
        mv "$MOODLE_DIR/public/config.php" "$MOODLE_DIR/config.php"
    fi

    # Hapus symlink broken
    if [ -L "$MOODLE_DIR/public/config.php" ] && [ ! -f "$MOODLE_DIR/public/config.php" ]; then
        echo "[DEV] ⚠️  Symlink broken, menghapus..."
        rm -f "$MOODLE_DIR/public/config.php"
    fi

    if [ -f "$MOODLE_DIR/config.php" ] && [ ! -e "$MOODLE_DIR/public/config.php" ]; then
        echo "[DEV] 🔗 Membuat symlink public/config.php → ../config.php"
        ln -sf "$MOODLE_DIR/config.php" "$MOODLE_DIR/public/config.php"
        echo "[DEV] ✅ Symlink dibuat!"
    fi
}

# ============================================
# Cek config.php
# ============================================
if [ ! -f "$MOODLE_DIR/config.php" ]; then
    echo ""
    echo "  ⚠️  config.php TIDAK ditemukan (fresh install)"
    echo "  ✅ Buka browser: ${MOODLE_WWWROOT:-http://localhost}/install.php"
    echo "  📋 Gunakan settings berikut saat instalasi:"
    echo "     - Database host   : ${PGSQL_HOST}"
    echo "     - Database name   : ${PGSQL_DATABASE}"
    echo "     - Database user   : ${PGSQL_USER}"
    echo "     - Data directory  : ${MOODLE_DATA}"
    echo "     - Moodle wwwroot  : ${MOODLE_WWWROOT:-http://localhost}"
    echo ""
    echo "  💾 config.php akan otomatis di-backup ke moodledata"
    echo ""

    # ✅ SAMA DENGAN PROD: Watcher di background
    (
        echo "[DEV] 👀 Watching untuk config.php..."
        WATCH_RETRIES=600
        WATCHED=0
        while [ $WATCHED -lt $WATCH_RETRIES ]; do
            sleep 1
            if [ -f "$MOODLE_DIR/config.php" ]; then
                echo "[DEV] ✅ config.php terdeteksi! Menyimpan backup..."
                cp "$MOODLE_DIR/config.php" "$CONFIG_BACKUP"
                chmod 640 "$CONFIG_BACKUP"
                echo "[DEV] ✅ Backup tersimpan di: $CONFIG_BACKUP"
                _setup_config_symlink
                echo "[DEV] 💡 Instalasi selesai, Moodle siap digunakan!"
                break
            fi
            WATCHED=$((WATCHED + 1))
        done
        if [ $WATCHED -eq $WATCH_RETRIES ]; then
            echo "[DEV] ⚠️  Timeout: config.php tidak ditemukan setelah 10 menit"
        fi
    ) &

else
    echo "[DEV] ✅ config.php ditemukan"

    _setup_config_symlink

    # Backup config.php jika belum ada
    if [ ! -f "$CONFIG_BACKUP" ]; then
        cp "$MOODLE_DIR/config.php" "$CONFIG_BACKUP"
        echo "[DEV] 💾 config.php di-backup ke $CONFIG_BACKUP"
    fi

    # Tunggu PostgreSQL
    echo "[DEV] Menunggu PostgreSQL..."
    MAX_RETRIES=30
    RETRY=0
    until pg_isready -h "${PGSQL_HOST}" -U "${PGSQL_USER}" -d "${PGSQL_DATABASE}" > /dev/null 2>&1; do
        RETRY=$((RETRY + 1))
        if [ "$RETRY" -ge "$MAX_RETRIES" ]; then
            echo "[DEV] ERROR: PostgreSQL tidak tersedia setelah ${MAX_RETRIES} percobaan"
            exit 1
        fi
        echo "[DEV] Menunggu postgres... ($RETRY/$MAX_RETRIES)"
        sleep 3
    done
    echo "[DEV] ✅ PostgreSQL siap!"
fi

# ============================================
# Setup cron jobs
# ✅ SAMA DENGAN PROD: hanya jika tidak ada argument
# ============================================
if [ $# -eq 0 ]; then
    echo "[DEV] Setting up cron..."
    /opt/scripts/cron.sh setup
fi

echo "[DEV] ✅ Container siap!"
echo "========================================"
echo ""

# ✅ SAMA DENGAN PROD: exec php-fpm atau custom command
if [ $# -eq 0 ]; then
    exec php-fpm
else
    exec "$@"
fi