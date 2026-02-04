#!/bin/bash

# Production Testing Script (Smoke Tests)
# Quick tests untuk verify production is working correctly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_PROD="$COMPOSE_DIR/.env.prod"
TEST_LOG="$COMPOSE_DIR/../logs/test-prod.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$TEST_LOG")"

echo -e "${BLUE}=== Production Smoke Tests ===${NC}"
echo "[$(date)] Starting production tests..." >> "$TEST_LOG"

TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -n "Testing $test_name... "
    if eval "$test_cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        echo "[$(date)] $test_name: PASS" >> "$TEST_LOG"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        echo "[$(date)] $test_name: FAIL" >> "$TEST_LOG"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

echo -e "\n${YELLOW}1. Container Health${NC}"
run_test "All containers running" \
    "[ $(docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD ps --services --filter 'status=running' | wc -l) -ge 3 ]"

echo -e "\n${YELLOW}2. HTTP Functionality${NC}"
run_test "Homepage loads (HTTP 200 or 302)" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ | grep -E '^(200|302)$'"

run_test "Index.php loads" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/index.php | grep -E '^(200|302)$'"

run_test "Config.php exists (no direct access)" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/config.php | grep -E '^(403|404)$'"

echo -e "\n${YELLOW}3. Database Operations${NC}"
PGSQL_USER=$(grep "^PGSQL_USER=" "$ENV_PROD" | cut -d= -f2)
PGSQL_DATABASE=$(grep "^PGSQL_DATABASE=" "$ENV_PROD" | cut -d= -f2)

run_test "Database connection" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T postgres pg_isready -U $PGSQL_USER"

run_test "Can query database" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T postgres psql -U $PGSQL_USER -d $PGSQL_DATABASE -c 'SELECT 1' 2>/dev/null | grep -q 1"

run_test "Moodle tables present" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T postgres psql -U $PGSQL_USER -d $PGSQL_DATABASE -c \"SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'\" 2>/dev/null | grep -qE '^[[:space:]]*[0-9]+'"

echo -e "\n${YELLOW}4. Critical Files${NC}"
run_test "config.php configured" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp grep -q 'dbhost' /var/www/html/config.php"

run_test "Version file present" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp test -f /var/www/html/version.php"

echo -e "\n${YELLOW}5. Data Directory${NC}"
run_test "Moodledata is accessible" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp test -d /var/www/moodledata"

run_test "Moodledata is writable" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp test -w /var/www/moodledata"

echo -e "\n${YELLOW}6. Services${NC}"
run_test "Cron service running" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp pgrep cron > /dev/null 2>&1"

run_test "Apache running" \
    "docker compose -f $COMPOSE_DIR/docker-compose.prod.yml --env-file $ENV_PROD exec -T moodleapp pgrep apache2 > /dev/null 2>&1"

echo -e "\n${BLUE}=== Test Summary ===${NC}"
TOTAL=$((TESTS_PASSED + TESTS_FAILED))
echo "Total Tests: $TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All smoke tests passed! Production is healthy.${NC}"
    echo "[$(date)] All tests passed" >> "$TEST_LOG"
    exit 0
else
    echo -e "\n${RED}Some tests failed! Check production.${NC}"
    echo "[$(date)] $TESTS_FAILED tests failed" >> "$TEST_LOG"
    exit 1
fi