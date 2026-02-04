#!/bin/bash

# Usage: ./backup-prod.sh

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

# desc backup
DESCRIPTION="${1:-manual}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/backup_prod_${DESCRIPTION}_${TIMESTAMP}.sql"

echo -e "\n${BLUE} Production Backup ${NC}"

#verify environment

if [ ! -f "$ENV_PROD" ]; then
    echo -e "${RED} ERROR: $ENV_PROD Not Found ${NC}"
    exit 1
fi


#create backup dir
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW} Backup Directory: ${NC}"

# get credential from .env.prod
PGSQL_USER=$(grep "^PGSQL_USER=" "$ENV_PROD" | cut -d= f2)
PGSQL_DATABASE=$(grep "^PGSQL_DATABASE=" "$ENV_PROD" | cut -d= f2)

echo -e "${YELLOW}Starting Backup ...${NC}"
echo "Database: $PGSQL_DATABASE"
echo "User: $PGSQL_USER"
echo "Backup FIle: $BACKUP_FILE"
echo ""

#create backup

if docker-compoes -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" \
    exec -T postgres \
    pg_dump -U "$PGSQL_USER" -d "$PGSQL_DATABASE" \
    > "$BACKUP_FILE" 2>> "$BACKUP_DIR/backup_error.log"; then

    #Check file size
    BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo "0")


    if [ "$BACKUP_SIZE" -gt 100 ]; then
        gzip "$BACKUP_FILE"
        COMPRESSED_SIZE=$(du -h "${BACKUP_FILE}.gz" | cut -f1)

        echo -e "${GREEN} Backup completed Successfull${NC}"
        echo -e "${GREEN} File: ${BACKUP_FILE}.gz${NC}"
        echo -e "${GREEN} size: ${BACKUP_SIZE}${NC}"
        echo ""

        #show recent backup
        echo -e "${BLUE} Recent backup:${NC}"
        ls -lh "$BACKUP_DIR"/backup_prod*.sql.gz 2>dev/null | tail -5 | awk '{print: $9, "("$5)"}'

    else
        rm -f "${BACKUP_FILE}"
        echo -e "${RED}ERROR: Backup file too small (size: $BACKUP_SIZE bytes) ${NC}"
        exit 1
    fi
else
    echo -e "${RED}ERROR: Backup failed${NC}"
    tail -20 "$BACKUP_DIR/backup_error.log"
    exit 1
fi


# Cleanup old backup (keep last 30 day)
echo -e "\n${YELLOW}Cleaning up old backups....${NC}"
DELETED=$(find "$BACKUP_DIR" -name "backup_prod*.sql.gz" -mtime +30 -delete -print | wc -l)
if [ "$DELETED" -gt 0 ]; then
    echo -e "${GREEN}Deleted $DELETED Old backup file ${NC}"

fi

echo -e "\n${GREEN}BACKUP COMPLETED ${NC}"

