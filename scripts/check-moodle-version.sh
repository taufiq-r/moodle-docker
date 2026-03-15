#!/bin/bash
# Script to monitor m00dle Version change

VERSION_FILE=/var/www/html/public/version.php
STATE_FILE=/var/www/moodledata/.last_version
LOG_FILE=${LOG_FILE:-/var/log/moodle-updates-version.log}

# [ ! -f "$VERSION_FILE" ] && { echo "[$(date)] version.php not found}" >> "$LOG_FILE"; exit 0; }

# Cek file ada
[ ! -f "$VERSION_FILE" ] && {
    echo "[$(date)] version.php not found: $VERSION_FILE" >> "$LOG_FILE"
    exit 0
}

# CURRENT_VERSION=$(grep -oP "^\\\$release\s*=\s*['\"]?\K[^'\"]*" "$VERSION_FILE" 2>/dev/null | head -1)

# Ambil versi dari version.php
# Format di Moodle: $release = '5.1 (Build: 20250101)';
CURRENT_VERSION=$(grep -oP '^\$release\s*=\s*['"'"'"]\K[^'"'"'"]+' "$VERSION_FILE" 2>/dev/null | head -1 | xargs)


# Fallback ke $version jika $release tidak ada
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION=$(grep -oP '^\$version\s*=\s*\K[\d.]+' "$VERSION_FILE" 2>/dev/null | head -1 | xargs)
fi

[ -z "$CURRENT_VERSION" ] && {
    echo "[$(date)] Tidak bisa baca versi dari version.php" >> "$LOG_FILE"
    exit 1
}

# [ -z "$CURRENT_VERSION" ] && CURRENT_VERSION=$(grep -oP "^\\\$version\s*=\s*\K\d+\.\d+" "$VERSION_FILE" 2>/dev/null | head -1)
# [ -z "$CURRENT_VERSION" ] && exit 1

LAST_VERSION=$(cat "$STATE_FILE" 2>/dev/null || echo "")

# ============================================
# Versi berubah
# ============================================
if [ "$CURRENT_VERSION" != "$LAST_VERSION" ]; then

    if [ -n "$LAST_VERSION" ]; then
        echo "[$(date)] ⬆️  Version changed: $LAST_VERSION → $CURRENT_VERSION" >> "$LOG_FILE"

        # ✅ FIX: Tambah slash di depan
        if /opt/scripts/backup.sh "upgrade_${LAST_VERSION}_to_${CURRENT_VERSION}"; then
            echo "[$(date)] ✅ Backup upgrade berhasil" >> "$LOG_FILE"

            /opt/scripts/notify-discord.sh "success" \
                "⬆️ Moodle Version Upgrade Detected" \
                "Versi berubah: **${LAST_VERSION}** → **${CURRENT_VERSION}**\nBackup otomatis berhasil dibuat."
        else
            echo "[$(date)] ❌ Backup upgrade gagal" >> "$LOG_FILE"

            /opt/scripts/notify-discord.sh "error" \
                "❌ Moodle Upgrade Backup Gagal" \
                "Versi berubah: **${LAST_VERSION}** → **${CURRENT_VERSION}**\nBackup otomatis GAGAL!\nCek log: /var/log/moodle-updates-version.log"
        fi
    else
        echo "[$(date)] Initial version recorded: $CURRENT_VERSION" >> "$LOG_FILE"

        /opt/scripts/notify-discord.sh "info" \
            "📋 Moodle Version Recorded" \
            "Versi Moodle terdeteksi: **${CURRENT_VERSION}**"
    fi

    echo "$CURRENT_VERSION" > "$STATE_FILE"

else
    echo "[$(date)] Version tidak berubah: $CURRENT_VERSION" >> "$LOG_FILE"
fi

# if [ "$CURRENT_VERSION" != "$LAST_VERSION" ]; then
#     if [ -n "$LAST_VERSION" ]; then
#         echo "[$(date)] Version changed: $LAST_VERSION -> $CURRENT_VERSION" >> "$LOG_FILE"
#         opt/scripts/backup.sh "upgrade_${LAST_VERSION}_to_${CURRENT_VERSION}"

#     else
#         echo "[$(date)] Initial version: $CURRENT_VERSION" >> "$LOG_FILE"
#     fi
#     echo "$CURRENT_VERSION" > "$STATE_FILE"
# fi


