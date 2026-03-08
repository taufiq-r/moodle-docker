#!/bin/bash
# Detect new plugin/theme BEFORE admin clicks "Upgrade now" and backup DB.
#
# Saat install dari browser (Plugin Directory / ZIP upload):
#   Moodle extract file → direktori plugin/tema berubah mtime  [STEP 1]
#   Admin klik "Upgrade now" → mdl_config_plugins diupdate     [STEP 2]
#
# Deteksi : mtime direktori          → berubah di STEP 1 (sebelum upgrade)
# Konfirm : upgrade.php --is-pending → exit 2 jika pending, 0 jika tidak
# Reset   : DB hash mdl_config_plugins → berubah di STEP 2 (setelah selesai)
#
# Moodle 5.1+:
#   MOODLE_ROOT   = /var/www/html        → CLI tools (admin/cli/)
#   MOODLE_PUBLIC = /var/www/html/public → web files (theme/, mod/, etc.)
#
# Alpine-compatible: menggunakan stat -c %Y sebagai pengganti find -printf %T@
# karena busybox find tidak support -printf

LOG_FILE=${LOG_FILE:-/var/log/moodle-preupgrade.log}
STATE_FILE=/var/www/moodledata/.last_upgrade_state
MTIME_HASH_FILE=/var/www/moodledata/.last_plugin_mtime_hash
DB_HASH_FILE=/var/www/moodledata/.preupgrade_db_hash
LOCK_FILE=/tmp/preupgrade.lock

MOODLE_ROOT=/var/www/html
MOODLE_PUBLIC=/var/www/html/public

WATCH_DIRS=(
    "$MOODLE_PUBLIC/theme"
    "$MOODLE_PUBLIC/mod"
    "$MOODLE_PUBLIC/blocks"
    "$MOODLE_PUBLIC/local"
    "$MOODLE_PUBLIC/auth"
    "$MOODLE_PUBLIC/enrol"
    "$MOODLE_PUBLIC/filter"
    "$MOODLE_PUBLIC/course/format"
    "$MOODLE_PUBLIC/report"
    "$MOODLE_PUBLIC/admin/tool"
    "$MOODLE_PUBLIC/question/type"
    "$MOODLE_PUBLIC/repository"
)

# --- Helper: run psql query (same pattern as check-plugin-updates.sh) ---
# run_psql() {
#     PGPASSWORD=$(cat "${MOODLE_DATABASE_PASSWORD_FILE}" 2>/dev/null) \
#     psql -h "$PGSQL_HOST" \
#          -U "$PGSQL_USER" \
#          -d "$PGSQL_DATABASE" \
#          -t -A \
#          -c "$1" 2>/dev/null
# }

run_psql() {
    PGPASSWORD="${PGSQL_PASSWORD}" \
    psql -h "$PGSQL_HOST" \
         -U "$PGSQL_USER" \
         -d "$PGSQL_DATABASE" \
         -t -A \
         -c "$1" 2>/dev/null
}

get_db_plugin_hash() {
    run_psql "
        SELECT md5(
            coalesce(
                (SELECT string_agg(plugin || value, ',' ORDER BY plugin)
                 FROM mdl_config_plugins
                 WHERE name='version'),'')
        );
    "
}

# -----------------------------------------------------------------------
# MTIME HASH — Alpine busybox compatible
# busybox find tidak support -printf %T@
# Gunakan: find subdirs → stat -c "%Y %n" untuk mtime + nama
# -----------------------------------------------------------------------
compute_mtime_hash() {
    local result=""
    for dir in "${WATCH_DIRS[@]}"; do
        [ ! -d "$dir" ] && continue
        # list semua subfolder langsung, lalu stat mtime-nya
        for subdir in "$dir"/*/; do
            [ -d "$subdir" ] && result+="$(stat -c "%Y %n" "$subdir" 2>/dev/null)\n"
        done
    done
    echo -e "$result" | sort | md5sum | cut -d' ' -f1
}

# --- Only one instance at a time ---
exec 9>"$LOCK_FILE" || exit 0
flock -n 9 || exit 0

[ ! -d "$MOODLE_PUBLIC" ] && {
    echo "[$(date)] MOODLE_PUBLIC not found: $MOODLE_PUBLIC" >> "$LOG_FILE"
    exit 0
}

CURRENT_MTIME_HASH=$(compute_mtime_hash)

[ -z "$CURRENT_MTIME_HASH" ] && {
    echo "[$(date)] Could not compute mtime hash, skipping" >> "$LOG_FILE"
    exit 0
}

LAST_MTIME_HASH=$(cat "$MTIME_HASH_FILE" 2>/dev/null || echo "")
LAST_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "idle")

# -----------------------------------------------------------------------
# CASE 1: mtime berubah & belum upgrading
# Konfirmasi dengan --is-pending sebelum backup
# -----------------------------------------------------------------------
if [ "$CURRENT_MTIME_HASH" != "$LAST_MTIME_HASH" ] && [ "$LAST_STATE" != "upgrading" ]; then

    cd "$MOODLE_ROOT" || exit 0
    php admin/cli/upgrade.php --is-pending > /dev/null 2>&1
    IS_PENDING=$?

    if [ "$IS_PENDING" = "2" ]; then
        echo "[$(date)] Plugin/theme change detected + upgrade pending confirmed → triggering pre-upgrade backup" >> "$LOG_FILE"

        CURRENT_DB_HASH=$(get_db_plugin_hash)

        if /opt/scripts/backup.sh "pre-upgrade"; then
            echo "$CURRENT_MTIME_HASH" > "$MTIME_HASH_FILE"
            echo "$CURRENT_DB_HASH" > "$DB_HASH_FILE"
            echo "upgrading" > "$STATE_FILE"
            echo "[$(date)] Pre-upgrade backup successful. State → upgrading" >> "$LOG_FILE"
        else
            echo "[$(date)] ERROR: Pre-upgrade backup failed" >> "$LOG_FILE"
        fi
    else
        # mtime berubah tapi tidak ada pending upgrade
        # (file dihapus, temp file, atau upgrade sudah selesai via GUI lebih cepat dari 1 menit)
        echo "[$(date)] Directory change detected but no pending upgrade (--is-pending exit: $IS_PENDING), updating mtime hash" >> "$LOG_FILE"
        echo "$CURRENT_MTIME_HASH" > "$MTIME_HASH_FILE"
    fi
    exit 0
fi

# -----------------------------------------------------------------------
# CASE 2: Sedang upgrading → cek apakah upgrade sudah selesai via DB
# -----------------------------------------------------------------------
if [ "$LAST_STATE" = "upgrading" ]; then
    CURRENT_DB_HASH=$(get_db_plugin_hash)
    DB_HASH_AT_BACKUP=$(cat "$DB_HASH_FILE" 2>/dev/null || echo "")

    if [ -z "$CURRENT_DB_HASH" ]; then
        echo "[$(date)] DB unreachable, skipping state check" >> "$LOG_FILE"
        exit 0
    fi

    if [ "$CURRENT_DB_HASH" != "$DB_HASH_AT_BACKUP" ]; then
        cd "$MOODLE_ROOT" || exit 0
        php admin/cli/upgrade.php --is-pending > /dev/null 2>&1
        IS_PENDING=$?

        if [ "$IS_PENDING" != "2" ]; then
            echo "$CURRENT_MTIME_HASH" > "$MTIME_HASH_FILE"
            echo "idle"                > "$STATE_FILE"
            rm -f "$DB_HASH_FILE"
            echo "[$(date)] Upgrade completed. State → idle" >> "$LOG_FILE"
        else
            echo "[$(date)] DB changed but upgrade still pending, waiting..." >> "$LOG_FILE"
        fi
    else
        echo "[$(date)] Waiting for admin to complete upgrade..." >> "$LOG_FILE"
    fi
    exit 0
fi

echo "[$(date)] No plugin/theme change detected" >> "$LOG_FILE"