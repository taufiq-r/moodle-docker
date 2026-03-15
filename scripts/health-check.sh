#!/bin/bash
# filepath: /home/taufiqr/moodle-docker/scripts/health-check.sh
# Health check komprehensif untuk Moodle
# Bisa dipanggil manual atau dari Docker healthcheck

set -e

MOODLE_ROOT=/var/www/html
MOODLE_PUBLIC=/var/www/html/public
MOODLE_DATA=/var/www/moodledata
LOG_FILE=${LOG_FILE:-/var/log/moodle-health.log}

FAILED=0
WARNINGS=0
RESULTS=()

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

check_pass() {
    RESULTS+=("✅ $1")
}

check_warn() {
    RESULTS+=("⚠️  $1")
    WARNINGS=$((WARNINGS + 1))
}

check_fail() {
    RESULTS+=("❌ $1")
    FAILED=$((FAILED + 1))
}

# ============================================
# 1. PHP-FPM
# ============================================
if php-fpm -t > /dev/null 2>&1; then
    check_pass "PHP-FPM config valid"
else
    check_fail "PHP-FPM config invalid"
fi

# ============================================
# 2. Moodle files
# ============================================
if [ -f "$MOODLE_PUBLIC/index.php" ]; then
    check_pass "Moodle public/index.php ada"
else
    check_fail "Moodle public/index.php tidak ditemukan"
fi

if [ -f "$MOODLE_ROOT/config.php" ]; then
    check_pass "config.php ada"
else
    check_warn "config.php tidak ditemukan (belum install?)"
fi

# ============================================
# 3. Moodledata writable
# ============================================
if [ -d "$MOODLE_DATA" ] && [ -w "$MOODLE_DATA" ]; then
    check_pass "moodledata writable"
else
    check_fail "moodledata tidak writable: $MOODLE_DATA"
fi

# ============================================
# 4. PostgreSQL reachable
# ============================================
if [ -n "$PGSQL_HOST" ] && [ -n "$PGSQL_USER" ]; then
    if pg_isready -h "$PGSQL_HOST" -U "$PGSQL_USER" > /dev/null 2>&1; then
        check_pass "PostgreSQL reachable ($PGSQL_HOST)"
    else
        check_fail "PostgreSQL tidak reachable ($PGSQL_HOST)"
    fi
else
    check_warn "PGSQL_HOST/PGSQL_USER tidak di-set, skip DB check"
fi

# ============================================
# 5. Disk space moodledata
# ============================================
if [ -d "$MOODLE_DATA" ]; then
    USAGE=$(df "$MOODLE_DATA" | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$USAGE" -lt 80 ]; then
        check_pass "Disk space OK (${USAGE}% used)"
    elif [ "$USAGE" -lt 90 ]; then
        check_warn "Disk space mulai penuh (${USAGE}% used)"
        /opt/scripts/notify-discord.sh "warning" \
            "⚠️ Disk Space Warning" \
            "Disk moodledata sudah **${USAGE}%** penuh!"
    else
        check_fail "Disk space kritis (${USAGE}% used)"
        /opt/scripts/notify-discord.sh "error" \
            "🚨 Disk Space Kritis!" \
            "Disk moodledata sudah **${USAGE}%** penuh! Segera bersihkan."
    fi
fi

# ============================================
# 6. PHP extensions Moodle
# ============================================
REQUIRED_EXTENSIONS="pdo_pgsql gd intl zip soap"
for EXT in $REQUIRED_EXTENSIONS; do
    if php -r "if(!extension_loaded('$EXT')) exit(1);" 2>/dev/null; then
        check_pass "PHP ext: $EXT"
    else
        check_fail "PHP ext missing: $EXT"
    fi
done

# ✅ FIX: opcache dicek via function karena nama internal berbeda
if php -r "if(!function_exists('opcache_get_status')) exit(1);" 2>/dev/null; then
    check_pass "PHP ext: opcache"
else
    check_fail "PHP ext missing: opcache"
fi

# ============================================
# Output hasil
# ============================================
log "========================================"
log "  Health Check Results"
log "========================================"
for RESULT in "${RESULTS[@]}"; do
    log "  $RESULT"
done
log "========================================"
log "  Total: ${#RESULTS[@]} checks | ❌ ${FAILED} failed | ⚠️  ${WARNINGS} warnings"
log "========================================"

# Kirim ke Discord jika ada kegagalan
if [ "$FAILED" -gt 0 ]; then
    SUMMARY=$(printf '%s\n' "${RESULTS[@]}" | tr '\n' '\n')
    /opt/scripts/notify-discord.sh "error" \
        "🚨 Moodle Health Check Failed" \
        "${FAILED} check gagal!\n\n${SUMMARY}"
    exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
    exit 0  # Warning tidak gagalkan healthcheck
fi

exit 0