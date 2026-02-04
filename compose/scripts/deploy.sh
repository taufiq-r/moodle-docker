#!/bin/bash

# Usage: ./deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR"
ENV_DEV_DIR="$COMPOSE_DIR/.env.dev"
ENV_PROD_DIR="$COMPOSE_DIR/.env.prod"
BACKUP_DIR="$SCRIPT_DIR/../backups"


# Colors
# RED='\033[0;31m'
# GREEN='\033[0;32m'
# YELLOW='\033[1;33m'
# NC='\033[0m'

#2. Verify Environments is healthy

echo -e "\n${YELLOW}1. Checking Environments....${NC}"
if [ -f "$ENV_DEV" ]; then
    echo -e "${RED}ERROR: $ENV_DEV not found${NC}"
    exit 1
fi

if [ ! -f "$ENV_PROD" ]; then
    echo -e "$RED}ERROR: $ENV_PROD not found${NC}"
    exit 1
fi
echo -e "${GREEN} Development environment healthy${NC}"

#3. pre deployment backup for production

echo -e "\n${YELLOW}3. Creating backup before deployment... ${NC}"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/backup_pre-deploy_$(date +%Y%m%d%_%H%M%S).sql"


if docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" --env-file "$ENV_PROD" exec -T postgres pg_dump -U $(grep PGSQL_USER "$ENV_PROD" | cut -d= -f2) -d $(grep PGSQL_DATABASE "$ENV_PROD" | cut -d= -f2) > "$BACKUP_FILE" 2>/dev/null; then
    if [ -s "$BACKUP_FILE" ]; then
        gzip "$BACKUP_FILE"
        BACKUP_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)
        echo -e "${GREEN} Production backup created: ${$BACKUP_FILE}.gz (size: $BACKUP_SIZE)${NC}"
    else
        rm -f "$BACKUP_FILE"
        echo -e "${YELLOW} Backup file is empty, skipping${NC}"
    fi
else
    echo -e "${YELLOW} Could not backup production (may be first run)${NC}"

fi


# 4. Prompt confirmation to process

echo  -e "\n${YELLOW}4. Confirm to Proceed Deployment${NC}"
echo  -e "About to deploy Development changes to ${RED}PRODUCTION${NC}"
read  -e "Are you sure? (y/n): " -r CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo -e "${YELLOW} Deployment cancelled by user.${NC}"
    exit 0
fi

#5. Stop production

echo -e "\n${YELLOW}5. Stopping production...${NC}"
docker compose -f "$COMPOSE_DIR/docker-compoes.prod.yml" --env-file "$ENV_PROD" down

#6. Sync from dev to prod  ( COPY Moodle Files )
echo -e "\n${YELLOW}6. Syncing Moodle files from Development to Production...${NC}"
#CODE is shared via ../moodle bind mount, so no need to copy
echo -e "${GREEN} moodle file shared (bind mount)${NC}"

#7. Start production with new file updates

echo -e "\n${YELLOW}7. Starting prodction ....${NC}"
docker compoes -f "$COMPOSE_DIR/docker-compose.prod.yml" --env-file "$ENV_PROD" up -d --env-file "$ENV_PROD" up --build -d

#8. Wait for service to be healthy

echo -e "\n${YELLOW}8.Waiting for service to be healty...${NC}"
MAX_RETRIES=30
RETRY=0

while [ $RETRY -lt $MAX_RETRIES ]; do
    HEALTH=$(docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" --env-filfe "$ENV_PROD" ps --services --filter "status=running" | wc -l)
    if [ "$HEALTH" -ge 2 ]; then
        echo -e "${GREEN}  Production services healthy${NC}"
        break
    fi
    RETRY=$((RETRY + 1))
    echo "Waiting ... (attempt $RETRY/$MAX_RETRIES)"
    sleep 3


done

if [ $RETRY -eq $MAX_RETRIES ]; then
    echo -e "${RED} ERROR: Production services failed to start within expected time.${NC}"
    exit 1
fi


#9 Health check

echo -e "\n${YELLOW}9. Running health cecks...${NC}"
sleep 10

if curl -f http:localhost:8080 >/dev/null 2>&1; then
    echo -e "${GREEN} Production is healty and responding${NC}"
else
    echo -e "${RED} ERROR: Production health check failed${NC}"
    exit 1
fi


echo -e "\n${GREEN}=== Deployment completed successfully ===${NC}"
echo -e "Production URL: http://localhost:8080"
echo -e "Backup file: ${BACKUP_FILE}.gz"
