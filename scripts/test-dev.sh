#!/bin/bash
# filepath: /home/taufiqr/moodle-docker/scripts/test-dev.sh
# Integration test untuk stack development
# Usage: ./scripts/test-dev.sh
# Exit code: 0 = semua pass, 1 = ada yang gagal

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env.dev"

# Load env
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)
else
    echo "❌ $ENV_FILE tidak ditemukan"
    exit 1
fi

COMPOSE_FILE="$PROJECT_DIR/docker-compose.dev.yml"
MOODLE_URL="${MOODLE_WWWROOT:-http://localhost}"
FAILED=0
PASSED=0
RESULTS=()

# ============================================
# Helpers
# ============================================
pass() {
    RESULTS+=("✅ $1")
    PASSED=$((PASSED + 1))
}

fail() {
    RESULTS+=("❌ $1")
    FAILED=$((FAILED + 1))
}

warn() {
    RESULTS+=("⚠️  $1")
}

section() {
    echo ""
    echo "▶ $1"
    echo "─────────────────────────────────────"
}

# ============================================
# 1. Cek file & struktur project
# ============================================
section "Project Structure"

REQUIRED_FILES=(
    "Dockerfile"
    "docker-compose.dev.yml"
    ".env.dev"
    "config/entrypoint/docker-entrypoint-dev.sh"
    "config/nginx/nginx-dev.conf"
    "config/php/99-moodle.ini"
    "scripts/backup.sh"
    "scripts/restore.sh"
    "scripts/cron.sh"
    "scripts/check-preupgrade.sh"
    "scripts/check-plugin-updates.sh"
    "scripts/check-moodle-version.sh"
    "scripts/health-check.sh"
    "scripts/notify-discord.sh"
)

for FILE in "${REQUIRED_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$FILE" ]; then
        pass "File ada: $FILE"
    else
        fail "File tidak ada: $FILE"
    fi
done

# Cek src/ ada isinya
if [ -f "$PROJECT_DIR/src/public/index.php" ]; then
    pass "Moodle source: src/public/index.php ada"
else
    fail "Moodle source: src/public/index.php tidak ditemukan (sudah clone?)"
fi

# ============================================
# 2. Cek Docker
# ============================================
section "Docker Environment"

if docker info > /dev/null 2>&1; then
    pass "Docker daemon running"
else
    fail "Docker daemon tidak berjalan"
    echo ""
    echo "❌ Docker tidak berjalan, test dihentikan"
    exit 1
fi

if docker compose version > /dev/null 2>&1; then
    pass "Docker Compose tersedia"
else
    fail "Docker Compose tidak tersedia"
fi

# ============================================
# 3. Build image
# ============================================
section "Docker Build"

echo "  Building image..."
if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
    build --quiet 2>/dev/null; then
    pass "Docker build berhasil"
else
    fail "Docker build gagal"
    echo ""
    echo "❌ Build gagal, test dihentikan"
    exit 1
fi

# ============================================
# 4. Start stack
# ============================================
section "Stack Startup"

echo "  Starting containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d 2>/dev/null

# Tunggu semua container healthy (max 120 detik)
echo "  Menunggu containers healthy..."
WAIT=0
MAX_WAIT=120
until [ $WAIT -ge $MAX_WAIT ]; do
    UNHEALTHY=$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        ps --format json 2>/dev/null | \
        python3 -c "
import sys, json
data = [json.loads(l) for l in sys.stdin if l.strip()]
unhealthy = [s['Name'] for s in data if s.get('Health','') not in ('healthy','')]
print(len(unhealthy))
" 2>/dev/null || echo "0")

    ALL_RUNNING=$(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        ps --format json 2>/dev/null | \
        python3 -c "
import sys, json
data = [json.loads(l) for l in sys.stdin if l.strip()]
not_running = [s['Name'] for s in data if s.get('State','') != 'running']
print(len(not_running))
" 2>/dev/null || echo "1")

    if [ "$ALL_RUNNING" = "0" ] && [ "$UNHEALTHY" = "0" ]; then
        break
    fi
    sleep 3
    WAIT=$((WAIT + 3))
    echo "  Waiting... (${WAIT}s/${MAX_WAIT}s)"
done

if [ $WAIT -ge $MAX_WAIT ]; then
    fail "Containers tidak healthy setelah ${MAX_WAIT}s"
else
    pass "Semua containers running & healthy (${WAIT}s)"
fi

# ============================================
# 5. Cek status setiap container
# ============================================
section "Container Status"

CONTAINERS=(
    "moodle-pgdb-dev"
    "moodle-web-dev"
    "moodle-nginx-dev"
    "moodle-cron-dev"
)

for CONTAINER in "${CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not found")
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "none")

    if [ "$STATUS" = "running" ]; then
        if [ "$HEALTH" = "healthy" ] || [ "$HEALTH" = "none" ]; then
            pass "Container $CONTAINER: $STATUS ($HEALTH)"
        else
            fail "Container $CONTAINER: $STATUS tapi health=$HEALTH"
        fi
    else
        fail "Container $CONTAINER: $STATUS"
    fi
done

# ============================================
# 6. Cek PostgreSQL
# ============================================
section "PostgreSQL"

if docker exec moodle-pgdb-dev \
    pg_isready -U "$PGSQL_USER" -d "$PGSQL_DATABASE" > /dev/null 2>&1; then
    pass "PostgreSQL accepting connections"
else
    fail "PostgreSQL tidak menerima koneksi"
fi

# Cek bisa query
TABLE_COUNT=$(docker exec moodle-pgdb-dev \
    psql -U "$PGSQL_USER" -d "$PGSQL_DATABASE" -t \
    -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" \
    2>/dev/null | tr -d ' \n' || echo "error")

if [ "$TABLE_COUNT" = "error" ]; then
    fail "PostgreSQL query gagal"
elif [ "${TABLE_COUNT:-0}" -gt 0 ]; then
    pass "PostgreSQL: Moodle tables ada ($TABLE_COUNT tables)"
else
    warn "PostgreSQL: Belum ada Moodle tables (belum install?)"
fi

# ============================================
# 7. Cek HTTP response
# ============================================
section "HTTP Response"

CONFIG_EXISTS=$(docker exec moodle-web-dev \
    test -f /var/www/html/config.php && echo "yes" || echo "no")

if [ "$CONFIG_EXISTS" = "no" ]; then
    # Belum install → 502 atau redirect ke install.php adalah normal
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "${MOODLE_URL}/" 2>/dev/null || echo "000")

    case "$HTTP_CODE" in
        302|303) pass "HTTP ${MOODLE_URL}/ → $HTTP_CODE (redirect ke install, normal)" ;;
        200)     pass "HTTP ${MOODLE_URL}/ → $HTTP_CODE" ;;
        502)     warn "HTTP ${MOODLE_URL}/ → 502 (config.php belum ada, buka /install.php)" ;;
        000)     fail "HTTP ${MOODLE_URL}/ → tidak bisa connect" ;;
        *)       warn "HTTP ${MOODLE_URL}/ → $HTTP_CODE (config.php belum ada)" ;;
    esac
else

# # Cek nginx up
# HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
#     --max-time 10 \
#     "${MOODLE_URL}/" 2>/dev/null || echo "000")

# case "$HTTP_CODE" in
#     200) pass "HTTP ${MOODLE_URL}/ → $HTTP_CODE OK" ;;
#     303|302|301) pass "HTTP ${MOODLE_URL}/ → $HTTP_CODE (redirect, normal)" ;;
#     000) fail "HTTP ${MOODLE_URL}/ → tidak bisa connect" ;;
#     *)   fail "HTTP ${MOODLE_URL}/ → $HTTP_CODE unexpected" ;;
# esac

# Cek health endpoint nginx
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    "${MOODLE_URL}/health" 2>/dev/null || echo "000")

if [ "$HEALTH_CODE" = "200" ]; then
    pass "Nginx health endpoint → $HEALTH_CODE OK"
else
    fail "Nginx health endpoint → $HEALTH_CODE"
fi


# ============================================
# 8. Cek PHP-FPM dalam container
# ============================================
section "PHP-FPM"

if docker exec moodle-web-dev php-fpm -t > /dev/null 2>&1; then
    pass "PHP-FPM config valid"
else
    fail "PHP-FPM config invalid"
fi

PHP_VERSION=$(docker exec moodle-web-dev php -r "echo PHP_VERSION;" 2>/dev/null)
if [ -n "$PHP_VERSION" ]; then
    pass "PHP version: $PHP_VERSION"
else
    fail "PHP tidak bisa dijalankan"
fi

# Cek required extensions
# ✅ FIX: opcache namanya "Zend OPcache" di php -m, tapi extension_loaded pakai "Zend OPcache"

REQUIRED_EXT="pdo_pgsql gd intl zip soap"
for EXT in $REQUIRED_EXT; do
    if docker exec moodle-web-dev \
        php -r "if(!extension_loaded('$EXT')){exit(1);}" 2>/dev/null; then
        pass "PHP ext: $EXT"
    else
        fail "PHP ext missing: $EXT"
    fi
done

# Cek opcache terpisah karena nama internalnya berbeda
if docker exec moodle-web-dev php -m 2>/dev/null | grep -qi "Zend OPcache"; then
    pass "PHP ext: opcache (Zend OPcache)"
else
    fail "PHP ext missing: opcache"
fi

# ============================================
# 9. Cek moodledata
# ============================================
section "Moodledata"

if docker exec moodle-web-dev test -d /var/www/moodledata; then
    pass "moodledata directory ada"
else
    fail "moodledata directory tidak ada"
fi

if docker exec moodle-web-dev test -w /var/www/moodledata; then
    pass "moodledata writable"
else
    fail "moodledata tidak writable"
fi

# Cek backup dir
if docker exec moodle-web-dev test -d /var/www/moodledata/backups; then
    pass "moodledata/backups directory ada"
else
    warn "moodledata/backups belum ada (akan dibuat saat backup pertama)"
fi

# ============================================
# 10. Cek scripts executable dalam container
# ============================================
section "Scripts"

SCRIPTS=(
    "/opt/scripts/backup.sh"
    "/opt/scripts/restore.sh"
    "/opt/scripts/cron.sh"
    "/opt/scripts/check-preupgrade.sh"
    "/opt/scripts/check-plugin-updates.sh"
    "/opt/scripts/check-moodle-version.sh"
    "/opt/scripts/health-check.sh"
    "/opt/scripts/notify-discord.sh"
)

for SCRIPT in "${SCRIPTS[@]}"; do
    if docker exec moodle-web-dev test -x "$SCRIPT" 2>/dev/null; then
        pass "Script executable: $(basename $SCRIPT)"
    else
        fail "Script tidak executable: $(basename $SCRIPT)"
    fi
done

# ============================================
# 11. Test backup.sh (dry run)
# ============================================
section "Backup Script"

if docker exec moodle-web-dev \
    bash -c "pg_dump --help > /dev/null 2>&1"; then
    pass "pg_dump tersedia di container"
else
    fail "pg_dump tidak tersedia di container"
fi

# Test backup aktual
if docker exec \
    -e PGSQL_PASSWORD="$PGSQL_PASSWORD" \
    moodle-web-dev \
    /opt/scripts/backup.sh "test" > /dev/null 2>&1; then
    pass "backup.sh test run berhasil"

    # Cek file backup ada
    BACKUP_COUNT=$(docker exec moodle-web-dev \
        find /var/www/moodledata/backups -name "backup_test_*.sql.gz" | wc -l)
    if [ "${BACKUP_COUNT:-0}" -gt 0 ]; then
        pass "Backup file terbuat ($BACKUP_COUNT file)"
    else
        fail "Backup file tidak ditemukan setelah backup"
    fi
else
    warn "backup.sh test gagal (mungkin DB belum ada data)"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "════════════════════════════════════════"
echo "  TEST SUMMARY — DEVELOPMENT"
echo "════════════════════════════════════════"
for RESULT in "${RESULTS[@]}"; do
    echo "  $RESULT"
done
echo "────────────────────────────────────────"
echo "  Total : $((PASSED + FAILED)) tests"
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
echo "════════════════════════════════════════"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "❌ Test GAGAL ($FAILED failures)"
    echo ""
    echo "Cek logs:"
    echo "  docker compose -f docker-compose.dev.yml --env-file .env.dev logs"
    exit 1
else
    echo "✅ Semua test PASSED!"
    exit 0
fi