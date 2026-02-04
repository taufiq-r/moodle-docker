#!/bin/bash

# Rollback Script
# Restore production dari backup jika deployment gagal

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_PROD="$COMPOSE_DIR/.env.prod"
BACKUP_DIR="$COMPOSE_DIR/../backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}=== Production Rollback ===${NC}"
echo "WARNING: This will restore production from backup"
echo ""

# List recent backups
echo -e "${YELLOW}Recent backups (pre-deploy):${NC}"
ls -lh "$BACKUP_DIR"/backup_pre-deploy*.sql.gz 2>/dev/null | tail -10 | awk '{print NR": "$9" ("$5")"}'

if [ ! -f "$BACKUP_DIR"/backup_pre-deploy*.sql.gz ]; then
    echo -e "${RED}ERROR: No pre-deploy backups found!${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Which backup to restore? (1-10, or full filename):${NC}"
read -p "Selection: " BACKUP_SELECTION

if [ ${#BACKUP_SELECTION} -gt 3 ]; then
    BACKUP_FILE="$BACKUP_SELECTION"
else
    BACKUP_FILE=$(ls -t "$BACKUP_DIR"/backup_pre-deploy*.sql.gz 2>/dev/null | sed -n "${BACKUP_SELECTION}p")
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}ERROR: Backup file not found!${NC}"
    exit 1
fi

echo -e "\n${YELLOW}Selected backup: $BACKUP_FILE${NC}"
read -p "Proceed with rollback? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Rollback cancelled"
    exit 0
fi

echo -e "\n${YELLOW}Starting rollback...${NC}"

# Stop production
echo -e "${YELLOW}Stopping production...${NC}"
docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" down

# Restore backup
echo -e "${YELLOW}Restoring database from backup...${NC}"
PGSQL_USER=$(grep "^PGSQL_USER=" "$ENV_PROD" | cut -d= -f2)
PGSQL_DATABASE=$(grep "^PGSQL_DATABASE=" "$ENV_PROD" | cut -d= -f2)

if gunzip -c "$BACKUP_FILE" | docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" \
    exec -T postgres psql -U "$PGSQL_USER" -d "$PGSQL_DATABASE" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database restored${NC}"
else
    echo -e "${RED}✗ Database restore failed!${NC}"
    exit 1
fi

# Start production
echo -e "${YELLOW}Starting production...${NC}"
docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" up -d

# Wait for services
sleep 10

# Health check
echo -e "${YELLOW}Running health check...${NC}"
if "$SCRIPT_DIR/health-check.sh" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Health check passed${NC}"
    echo -e "\n${GREEN}=== Rollback completed successfully ===${NC}"
    exit 0
else
    echo -e "${RED}✗ Health check failed!${NC}"
    echo -e "${RED}Production may still be in inconsistent state${NC}"
    exit 1
fi