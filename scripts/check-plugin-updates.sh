#!/bin/bash
# Backup when theme/plugin installed or upgraded

LOG_FILE=/var/log/moodle-plugin-updates.log
STABLE_STATE_FILE=/var/www/moodledata/.last_plugin_hash
LAST_SEEN_HASH_FILE=/var/www/moodledata/.last_seen_hash
CHANGE_TIME_FILE=/var/www/moodledata/.last_hash_change_time
STABLE_WINDOW=120   # detik hash harus stabil (2 menit)

run_psql() {
    PGPASSWORD="${PGSQL_PASSWORD}" \
    psql -h "$PGSQL_HOST" \
         -U "$PGSQL_USER" \
         -d "$PGSQL_DATABASE" \
         -t -A \
         -c "$1" 2>/dev/null
}

CURRENT_HASH=$(run_psql "
SELECT md5(
    coalesce(
        (SELECT string_agg(plugin || value, ',' ORDER BY plugin)
         FROM mdl_config_plugins
         WHERE name='version'),'')
);
")

# Skip jika DB tidak bisa diakses
[ -z "$CURRENT_HASH" ] && {
    echo "[$(date)] DB unreachable, skipping" >> "$LOG_FILE"
    exit 0
}

LAST_SEEN_HASH=$(cat "$LAST_SEEN_HASH_FILE" 2>/dev/null || echo "")
LAST_STABLE_HASH=$(cat "$STABLE_STATE_FILE" 2>/dev/null || echo "")
LAST_CHANGE_TIME=$(cat "$CHANGE_TIME_FILE" 2>/dev/null || echo 0)
NOW=$(date +%s)


#exit if no change detected
# CASE 1: Hash baru berubah → catat, tunggu stabil  
if [ "$CURRENT_HASH" != "$LAST_SEEN_HASH" ]; then
    echo "$CURRENT_HASH" > "$LAST_SEEN_HASH_FILE"
    echo "$NOW"          > "$CHANGE_TIME_FILE"
    echo "[$(date)] Hash change detected, waiting for stability (${STABLE_WINDOW}s)..." >> "$LOG_FILE"
    
    /opt/scripts/notify-discord.sh "info" \
        "🔌 Plugin/Theme Change Detected" \
        "Perubahan plugin/theme terdeteksi.\nMenunggu stabilisasi ${STABLE_WINDOW} detik sebelum backup..."
    exit 0
fi

# HASH Already STABLE

if [ "$CURRENT_HASH" != "$LAST_STABLE_HASH" ]; then
    ELAPSED=$((NOW - LAST_CHANGE_TIME))

    if [ "$ELAPSED" -ge "$STABLE_WINDOW" ]; then
        echo "[$(date)] Hash stabil selama ${ELAPSED}s → trigger backup" >> "$LOG_FILE"

        if /opt/scripts/backup.sh "plugin-change"; then
            echo "$CURRENT_HASH" > "$STABLE_STATE_FILE"
            echo "[$(date)] ✅ Backup plugin-change berhasil" >> "$LOG_FILE"

            /opt/scripts/notify-discord.sh "success" \
                "✅ Plugin/Theme Backup Berhasil" \
                "Backup otomatis setelah perubahan plugin/theme selesai."
        else
            echo "[$(date)] ❌ Backup plugin-change gagal" >> "$LOG_FILE"

            /opt/scripts/notify-discord.sh "error" \
                "❌ Plugin/Theme Backup Gagal" \
                "Backup otomatis setelah perubahan plugin/theme GAGAL!\nCek log: /var/log/moodle-plugin-updates.log"
        fi
    else
        echo "[$(date)] Menunggu stable window... (${ELAPSED}/${STABLE_WINDOW}s)" >> "$LOG_FILE"
    fi
    exit 0
fi

# if [ "$CURRENT_HASH" != "$LAST_STABLE_HASH" ]; then
#     if [ $((NOW - LAST_CHANGE_TIME)) -ge $STABLE_WINDOW ]; then
#         echo "[$(date)] Hash stable → backup triggered" >> "$LOG_FILE"
#         if /opt/scripts/backup.sh plugin-change; then
#             echo "$CURRENT_HASH" > "$STABLE_STATE_FILE"
#         else
#             echo "[$(date)] ERROR: Backup failed" >> "$LOG_FILE"
#         fi

#     else
#         echo "[$(date)] Waiting for stable window..." >> "$LOG_FILE"
#     fi
#     exit 0
# fi
#no change

echo "[$(date)] No plugin/theme change" >> "$LOG_FILE"
