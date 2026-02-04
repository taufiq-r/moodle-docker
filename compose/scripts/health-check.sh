#!/bin/bash

# usage: ./health-check.sh [--detailed] [--email user/admin@example.com]


SCRIPT_DIR="$(cd "$dirname "${BACKUP_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
ENV_PROD="$COMPOSE_DIR/.env.prod"
LOG_FILE="$COMPOSE_DIR/../logs/health-check.log"


#COLOR
RED='\033[0;31m'
GREEN='\033[0,32m'
YELLOW='\033[1,33m'
BLUE='\033[0,34m'
NC='\033[0m'


#Parse args

DETAILED=false
EMAIL=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --detailed) DETAILED=true; shift ;;
        --email) EMAIL="$2"; shift 2 ;;
        *) shift ;;
    esac
done

#craete log directory

mkdir -p "$dirname "$LOG_FILE")"

echo "[$(date)] Starting Health Check... " >> "$LOG_FILE"

# Initialize status
OVERALL_STATUS="HEALTHY"
ISSUES=()

echo -e "${YELLOW}1. Docker containers${NC}"
echo "Timestamp: $(date)"
echo ""


# 1. Check docker containers
echo -e "\n${YELLOW}1. Docker containers${NC}"
SERVICES=("moodle-web-prod "moodle-pgdb-prod "pgadmin-prod")
for services in "${SERVICES[$]}"; do
    if docker ps --filter "name=$services:" --filter "status=running" --quiet | grep -q ;then
        echo -e "${GREEN} ${NC} $services: Running"
        echo "[$(date)] $services: Running" >> "$LOG_FILE"

    else
        echo -e "${RED} ${NC} $services: Not Running"
        echo "[$(date)] $services: FAILED" >> "$LOG_FILE"
        OVERALL_STATUS="UNHEALTHY"
        ISSUES+=("Container $service is not running")
    fi

done    


# 2. Check moodle http response

echo -e "\n${YELLOW}2. Moodle web services${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http:localhost:8080/ 2> /dev/null || echo "000" )
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then 
    echo -e "${GREEN} ${NC} HTTP STATUS: $HTTP_CODE"
    echo "[$(date)] Moodle HTTP: $HTTP_CODE" >> "$LOG_FILE"
else
    echo -e "${RED} ${NC} HTTP STATUS $HTTP_CODE"
    echo "[$(date)] Moodle HTTP: FAILED ($HTTP_CODE) >> $LOG_FILE"
    OVERALL_STATUS="UNHEALTY"
    ISSUE+=("Moodle HTTP STATUS is $HTTP_CODE")

fi


# 3. Check Postgres

echo -e "\n${YELLOW}3. Postgres Database ${NC}"
PGSQL_USER=$(grep "^PGSQL_USER=" "$ENV_PROD" | cut -d= -f2)
PGSQL_DATABASE=$(grep "^PGSQL_DATABASE=" "$ENV_PROD" | cut -d= -f2)

if docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" \
    exec -T postgres \
    pg_isready -U  "$PGSQL_USER" >/dev/null 2>&1; then
    echo -e "${GREEN} ${NC} PostgreSQL: Healthy"
    echo "[$(date)] PostgreSQL: Healthy:" >> "$LOG_FILE" 

else
    echo -e "${RED}${NC} PostgreSQL: Not Responding"
    echo "[$(date)] PostgreSQL: FAILED" >> "$LOG_FILE"
    OVERALL_STATUS="UNHEALTHY"
    ISSUES+=("PostgreSQL is not responding")
fi

# 4. Check Disk 
echo -e "\n${YELLOW}4. Disk Space${NC}"
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed '5/%//')
DISK_THRESHOLD=80
if [ "$DISK_USAGE" -lt "$DISK_THRESHOLD"]; then
    echo -e "${GREEN}${NC} Disk Usage: $DISK_USAGE%"
    echo "[$(date)] Disk: $DISK_USAGE%" >> "$LOG_FILE"
else
    echo -e "${RED}${NC} Disk Usage: $DISK_USAGE% (threshold: $DISK_THRESHOLD%)"
    echo "[$(date)] Disk: CRITICAL ($DISK_USAGE%)" >> "$LOG_FILE"
    OVERALL_STATUS="UNHEALTHY"
    ISSUES+=("Disk usage is $DISK_USAGE")

fi


#5. Check backup status

echo -e "\n${YELLOW} Check Backup Status ${NC}"
BACKUP_DIR="$COMPOSE_DIR/../backups"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/backup_prod*.sql.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${YELLOW}${NC} No BACKUP found"
    echo "[$(date)] BACKUP: No BACKUP found" >> "$LOG_FILE"

else
    BACKUP_AGE=$(find "$LATEST_BACKUP" -mtime +1 2>/dev/null)
    if [ -z "$BACKUP_AGE" ]; then
        echo -e "${GREEN}${NC} Latest BACKUP: $(basename "$LATEST_BACKUP") ($(du -h "$LATEST_BACKUP" | cut -f1))"
        echo "[$(date)] Backup: Fresh" >> "$LOG_FILE"
    else 
        echo -e "${YELLOW}${NC} Latest BACKUP is older than 1 day"
        echo "[$(date)] Backup: Outdated" >> "$LOG_FILE"
        ISSUES+=("Latest backup is older than 1 day")

    fi
fi

#6. Check moodle data directory

echo -e "\n${YELLOW}6. Data Directory${NC}"
MOODLE_DATA_SIZE=$(docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
    --env-file "$ENV_PROD" \
    exec -T  moodleapp\
    du -sh /var/www/moodledata 2>/dev/null | cut -f1 || echo "uknown")
echo -e "${GREEN}${NC} Moodle data size: $MOODLE_DATA_SIZE"
echo "[$(date)] MOodle data: $MOODLE_DATA_SIZE" >> "$LOG_FILE"


#SUMMARY

echo -e "\n${BLUE} Summary${NC}"
if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
    echo -e "${GREEN}Overall status: HEALTHY${NC}"
    echo "[$(date)] Overall: HEALTHY" >> "$LOG_FILE"

else
    echo -e "${RED} Overall status: UNHEALTHY${NC}"
    echo "[$(date)] OVerall status: UNHEALTHY" >> "$LOG_FILE"
    echo -e "\n${RED}Issues found:${NC}"

    for issue in "{$ISSUES[@]}"; do
        echo -e "${RED} - $issue${NC}"
        echo "[$(date)] Issue: $issue" >> "$LOG_FILE"

    done
fi


# Detailed info if requestd

if [ "$DETAILED" = true ]; then
    echo -e "\n${YELLOW}Container Status: ${NC}"
    docker compose -f "$COMPOSE_DIR/docker-compose.prod.yml" \
        --env-file "$ENV_PROD" ps

    echo -e "\n${YELLOW}Recent logs (Moodle):${NC}"
    docker logs --tail 10 moodle-web-prod 2>/dev/null || echo "N/A"

    echo -e"\n${YELLOW}Recent logs (Database):${NC}"
    docker logs --tail 10 moodle-pgdb-prod 2>/dev/null || echo "N/A"

fi

#Send email aleert if issue and email provided

if [ "$OVERALL_STATUS" != "HEALTHY" ] && [ -n "$EMAIL" ]; then
    echo -e "\n${YELLOW}Sending alert email to $EMAIL..${NC}"
    {
        echo "Production Health Check Failed"
        echo "Time: $(date)"
        echo ""
        echo "Issues"
        for issue in "${ISSUES[@]}"; do
            echo " -$issue"
        done
        echo ""
        echo "Check logs: $LOG_FILE"
        
    } | mail -S "ALERT: Moodle Production Check Failed" "$EMAIL" 2>/dev/null || echo "Email sending failed"

fi

echo -e "\n${BLUE}Health check completed at $(date)${NC}"
echo "[$(date)] Health Check completed" >> "$LOG_FILE"

#exit with appropciate code

if [ "$OVERALL_STATUS" = "HEALTHY" ]; then
    exit 0
else
    exit 1
fi
