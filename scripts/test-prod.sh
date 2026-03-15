#!/bin/bash
# filepath: /home/taufiqr/moodle-docker/scripts/test-prod.sh
# Integration test untuk stack production
# Usage: ./scripts/test-prod.sh [--keep-running]
# Exit code: 0 = semua pass, 1 = ada yang gagal

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env.prod"
KEEP_RUNNING=false

# Parse args
for ARG in "$@"; do
    case $ARG in
        --keep-running) KEEP_RUNNING=true ;;
    esac
done

# Load env
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | grep -v '^$' | xargs)
else
    echo "❌ $ENV_FILE tidak ditemukan"
    exit 1
fi

COMPOSE_FILE="$PROJECT_DIR/docker-compose.prod.yml"
MOODLE_URL="${MOODLE_WWWROOT:-http://localhost}"
FAILED=0
PASSED=0
RESULTS=()

# ============================================
# Helpers (sama dengan test-dev.sh)
# ============================================
pass() { RESULTS+=("✅ $1"); PASSED=$((PASSED + 1)); }
fail() { RESULTS+=("❌ $1"); FAILED=$((FAILED + 1)); }
warn() { RESULTS+=("⚠️  $1"); }

section() {
    echo ""
    echo "▶ $1"
    echo "─────────────────────────────────────"
}

cleanup() {
    if [ "$KEEP_RUNNING" = false ]; then
        echo ""
        echo "  Stopping containers..."
        docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down > /dev/null 2>&1
        echo "  Containers stopped"
    else
        echo "  --keep-running: containers dibiarkan berjalan"
    fi
}

trap cleanup EXIT

# ============================================
# 1. Pre-flight checks (sebelum start container)
# ============================================
section "Pre-flight Checks"

# Cek .env.prod ada dan tidak pakai nilai default berbahaya
if grep -q "CHANGE_ME\|your_password\|example.com" "$ENV_FILE" 2>/dev/null; then
    fail ".env.prod masih menggunakan nilai default/placeholder"
else
    pass ".env.prod tidak ada nilai placeholder"
fi

# Cek MOODLE_WWWROOT bukan localhost untuk prod
if echo "$MOODLE_WWWROOT" | grep -qE "localhost|127\.0\.0\.1"; then
    warn "MOODLE_WWWROOT masih localhost (oke untuk test, tidak untuk deploy)"
else
    pass "MOODLE_WWWROOT: $MOODLE_WWWROOT"
fi

# Cek secrets
REQUIRED_FILES=(
    "Dockerfile"
    "docker-compose.prod.yml"
    ".env.prod"
    "config/entrypoint/docker-entrypoint-prod.sh"
    "config/nginx/nginx-prod.conf"
    "config/php/99-moodle.ini"
    "scripts/backup.sh"
    "scripts/restore.sh"
    "scripts/cron.sh"
    "scripts/health-check.sh"
    "scripts/notify-discord.sh"
)

section "Project Structure"

for FILE in "${REQUIRED_FILES[@]}"; do
    if [ -f "$PROJECT_DIR/$FILE" ]; then
        pass "File ada: $FILE"
    else
        fail "File tidak ada: $FILE"
    fi
done

if [ -f "$PROJECT_DIR/src/public/index.php" ]; then
    pass "Moodle source: src/public/index.php ada"
else
    fail "Moodle source: src/public/index.php tidak ditemukan"
fi

# ============================================
# 2. Docker
# ============================================
section "Docker Environment"

if docker info > /dev/null 2>&1; then
    pass "Docker daemon running"
else
    fail "Docker daemon tidak berjalan"
    exit 1
fi

# ============================================
# 3. Build
# ============================================
section "Docker Build (Production)"

echo "  Building production image..."
if docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
    build --quiet 2>/dev/null; then
    pass "Production image build berhasil"
else
    fail "Production image build gagal"
    exit 1
fi

# Cek image size (production image tidak boleh terlalu besar)
IMAGE_SIZE=$(docker image inspect \
    $(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        config --format json 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(list(d['services'].values())[0].get('image',''))" \
        2>/dev/null) \
    --format='{{.Size}}' 2>/dev/null || echo "0")

IMAGE_SIZE_MB=$((${IMAGE_SIZE:-0} / 1024 / 1024))
if [ "$IMAGE_SIZE_MB" -lt 500 ]; then
    pass "Image size: ${IMAGE_SIZE_MB}MB (optimal)"
elif [ "$IMAGE_SIZE_MB" -lt 800 ]; then
    warn "Image size: ${IMAGE_SIZE_MB}MB (acceptable)"
else
    warn "Image size: ${IMAGE_SIZE_MB}MB (besar, pertimbangkan optimasi)"
fi

# ============================================
# 4. Start stack
# ============================================
section "Stack Startup"

echo "  Starting production containers..."
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d 2>/dev/null

echo "  Menunggu containers healthy..."
WAIT=0
MAX_WAIT=180  # prod lebih lama karena start_period lebih panjang

until [ $WAIT -ge $MAX_WAIT ]; do
    ALL_HEALTHY=true
    while IFS= read -r CONTAINER; do
        STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null)
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
            "$CONTAINER" 2>/dev/null)

        if [ "$STATUS" != "running" ]; then
            ALL_HEALTHY=false
            break
        fi
        if [ "$HEALTH" = "starting" ]; then
            ALL_HEALTHY=false
            break
        fi
    done < <(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        ps --format "{{.Name}}" 2>/dev/null)

    $ALL_HEALTHY && break
    sleep 5
    WAIT=$((WAIT + 5))
    echo "  Waiting... (${WAIT}s/${MAX_WAIT}s)"
done

if [ $WAIT -ge $MAX_WAIT ]; then
    fail "Containers tidak healthy setelah ${MAX_WAIT}s"
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps
else
    pass "Semua containers running & healthy (${WAIT}s)"
fi

# ============================================
# 5. Container status
# ============================================
section "Container Status"

CONTAINERS=(
    "moodle-pgdb-prod"
    "moodle-web-prod"
    "moodle-nginx-prod"
    "moodle-cron-prod"
)

for CONTAINER in "${CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "not found")
    HEALTH=$(docker inspect \
        --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$CONTAINER" 2>/dev/null || echo "none")

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
# 6. Security checks (khusus prod)
# ============================================
section "Security Checks"

# Cek container tidak jalan sebagai root
APP_USER=$(docker exec moodle-web-prod \
    php -r "echo get_current_user();" 2>/dev/null || echo "unknown")
if [ "$APP_USER" = "root" ]; then
    fail "PHP-FPM berjalan sebagai root (security risk)"
else
    pass "PHP-FPM user: $APP_USER (bukan root)"
fi

# Cek tidak ada debug mode di prod
if docker exec moodle-web-prod \
    grep -q "debug\s*=\s*true\|DEBUG.*=.*true" /var/www/html/config.php 2>/dev/null; then
    fail "Debug mode aktif di production!"
else
    pass "Debug mode tidak aktif"
fi

# Cek config.php permissions
CONFIG_PERM=$(docker exec moodle-web-prod \
    stat -c "%a" /var/www/html/config.php 2>/dev/null || echo "000")
if [ "$CONFIG_PERM" = "640" ] || [ "$CONFIG_PERM" = "600" ]; then
    pass "config.php permissions: $CONFIG_PERM (aman)"
else
    warn "config.php permissions: $CONFIG_PERM (disarankan 640)"
fi

# ============================================
# 7. HTTP & Headers
# ============================================
section "HTTP Response & Security Headers"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 15 \
    "${MOODLE_URL}/" 2>/dev/null || echo "000")

case "$HTTP_CODE" in
    200|303|302|301) pass "HTTP ${MOODLE_URL}/ → $HTTP_CODE" ;;
    000) fail "HTTP ${MOODLE_URL}/ → tidak bisa connect" ;;
    *)   fail "HTTP ${MOODLE_URL}/ → $HTTP_CODE unexpected" ;;
esac

# Cek security headers
HEADERS=$(curl -s -I --max-time 10 "${MOODLE_URL}/" 2>/dev/null)

for HEADER in "X-Frame-Options" "X-Content-Type-Options" "X-XSS-Protection"; do
    if echo "$HEADERS" | grep -qi "$HEADER"; then
        pass "Security header ada: $HEADER"
    else
        warn "Security header tidak ada: $HEADER"
    fi
done

# Cek health endpoint
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 5 \
    "${MOODLE_URL}/health" 2>/dev/null || echo "000")

if [ "$HEALTH_CODE" = "200" ]; then
    pass "Nginx health endpoint → $HEALTH_CODE"
else
    fail "Nginx health endpoint → $HEALTH_CODE"
fi

# ============================================
# 8. PostgreSQL
# ============================================
section "PostgreSQL"

if docker exec moodle-pgdb-prod \
    pg_isready -U "$PGSQL_USER" -d "$PGSQL_DATABASE" > /dev/null 2>&1; then
    pass "PostgreSQL accepting connections"
else
    fail "PostgreSQL tidak menerima koneksi"
fi

TABLE_COUNT=$(docker exec moodle-pgdb-prod \
    psql -U "$PGSQL_USER" -d "$PGSQL_DATABASE" -t \
    -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'mdl_%';" \
    2>/dev/null | tr -d ' \n' || echo "error")

if [ "$TABLE_COUNT" = "error" ]; then
    fail "PostgreSQL query gagal"
elif [ "${TABLE_COUNT:-0}" -gt 0 ]; then
    pass "PostgreSQL: Moodle tables ada ($TABLE_COUNT tables)"
else
    warn "PostgreSQL: Belum ada Moodle tables"
fi

# ============================================
# 9. Named volume moodle-public
# ============================================
section "Shared Volumes"

# Cek nginx bisa akses /public dari named volume
if docker exec moodle-nginx-prod \
    test -f /var/www/html/public/index.php 2>/dev/null; then
    pass "Nginx dapat akses public/index.php via named volume"
else
    fail "Nginx tidak bisa akses public/index.php"
fi

# ============================================
# 10. Backup test
# ============================================
section "Backup Script"

if docker exec \
    -e PGSQL_PASSWORD="$PGSQL_PASSWORD" \
    moodle-web-prod \
    /opt/scripts/backup.sh "test" > /dev/null 2>&1; then
    pass "backup.sh test run berhasil"
else
    warn "backup.sh test gagal (mungkin DB belum ada data)"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "════════════════════════════════════════"
echo "  TEST SUMMARY — PRODUCTION"
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
    exit 1
else
    echo "✅ Semua test PASSED!"
    if [ "$KEEP_RUNNING" = false ]; then
        echo "  (containers akan di-stop)"
    fi
    exit 0
fi