#!/bin/bash

# Development Testing Script
# Test features dan functionality di development environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_DEV="$COMPOSE_DIR/.env.dev"
TEST_LOG="$COMPOSE_DIR/../logs/test-dev.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$(dirname "$TEST_LOG")"

echo -e "${BLUE}=== Development Testing ===${NC}"
echo "[$(date)] Starting development tests..." >> "$TEST_LOG"

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

echo -e "\n${YELLOW}1. Container Health Tests${NC}"
run_test "Moodle container running" \
    "docker ps --filter 'name=moodle-web-dev' --filter 'status=running' --quiet | grep -q ."

run_test "PostgreSQL container running" \
    "docker ps --filter 'name=moodle-pgdb-dev' --filter 'status=running' --quiet | grep -q ."

run_test "pgAdmin container running" \
    "docker ps --filter 'name=pgadmin-dev' --filter 'status=running' --quiet | grep -q ."

echo -e "\n${YELLOW}2. HTTP Tests${NC}"
run_test "Moodle accessible on port 8080" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/ | grep -E '^(200|302|303)$'"

run_test "Moodle index.php accessible" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/index.php | grep -E '^(200|302|303)$'"

run_test "pgAdmin accessible on port 81" \
    "curl -s -o /dev/null -w '%{http_code}' http://localhost:81/ | grep -E '^(200|301|302|303)$'"

echo -e "\n${YELLOW}3. Database Tests${NC}"
run_test "PostgreSQL responding to queries" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T postgres pg_isready -U moodle_dev"

run_test "Moodle database exists" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T postgres psql -U moodle_dev -d moodle_dev -c '\q' 2>/dev/null"

run_test "Moodle tables exist" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T postgres psql -U moodle_dev -d moodle_dev -c \"SELECT count(*) FROM information_schema.tables WHERE table_schema='public'\" 2>/dev/null | grep -qE '[0-9]'"

echo -e "\n${YELLOW}4. Moodle Configuration Tests${NC}"
run_test "config.php exists" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -f /var/www/html/config.php"

run_test "Moodle version.php accessible" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -f /var/www/html/version.php"

run_test "Moodle lib/setup.php exists" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -f /var/www/html/lib/setup.php"

echo -e "\n${YELLOW}5. File Permission Tests${NC}"
run_test "moodledata directory writable" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -w /var/www/moodledata"

run_test "moodledata owned by www-data" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp stat -c '%U' /var/www/moodledata | grep -q www-data"

echo -e "\n${YELLOW}6. Cron Tests${NC}"
run_test "Cron service running" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp pgrep cron > /dev/null 2>&1"

run_test "Backup script exists" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -f /usr/local/bin/moodle-backup.sh"

run_test "Version check script exists" \
    "docker compose -f $COMPOSE_DIR/docker-compose.dev.yml --env-file $ENV_DEV exec -T moodleapp test -f /usr/local/bin/check-moodle-version.sh"

echo -e "\n${YELLOW}7. Backup Tests${NC}"
BACKUP_DIR="$COMPOSE_DIR/../backups"
run_test "Backup directory exists" \
    "test -d $BACKUP_DIR"

run_test "Recent backups exist" \
    "find $BACKUP_DIR -name 'backup_*.sql.gz' -mtime -7 2>/dev/null | grep -q ."

echo -e "\n${BLUE}=== Test Summary ===${NC}"
TOTAL=$((TESTS_PASSED + TESTS_FAILED))
echo "Total Tests: $TOTAL"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    echo "[$(date)] All tests passed" >> "$TEST_LOG"
    exit 0
else
    echo -e "\n${RED}Some tests failed!${NC}"
    echo "[$(date)] $TESTS_FAILED tests failed" >> "$TEST_LOG"
    exit 1
fi