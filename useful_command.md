# Moodle Docker - Useful Commands Guide

## 📋 Table of Contents
1. [Container Management](#container-management)
2. [Logs & Monitoring](#logs--monitoring)
3. [Database Management](#database-management)
4. [Backup & Restore](#backup--restore)
5. [File Management](#file-management)
6. [Troubleshooting](#troubleshooting)
7. [Cleanup & Reset](#cleanup--reset)

---

## Container Management

### Start All Containers
```bash
docker-compose up -d
```
Menjalankan semua containers (moodleapp, postgres, pgadmin) di background.

### Stop All Containers
```bash
docker-compose down
```
Menghentikan semua containers tanpa menghapus volumes (data tetap aman).

### Restart All Containers
```bash
docker-compose restart
```
Restart semua containers yang sedang running.

### Rebuild & Start
```bash
docker-compose up -d --build
```
Rebuild image Dockerfile dan start containers (gunakan saat ada perubahan code).

### View Running Containers
```bash
docker-compose ps
```
Menampilkan status semua containers.

### Start Specific Container
```bash
docker-compose up -d moodleapp
docker-compose up -d postgres
docker-compose up -d pgadmin
```

### Stop Specific Container
```bash
docker-compose stop moodleapp
docker-compose stop postgres
```

### Remove Specific Container (data tetap)
```bash
docker-compose rm -f moodleapp
```

---

## Logs & Monitoring

### View Moodle Logs (Real-time)
```bash
docker logs -f moodle-web
```
`-f` = follow (streaming logs). Tekan `Ctrl+C` untuk exit.

### View Moodle Logs (Last 100 lines)
```bash
docker logs --tail 100 moodle-web
```

### View PostgreSQL Logs
```bash
docker logs -f moodle-pgdb
```

### View pgAdmin Logs
```bash
docker logs -f moodle-docker-pgadmin-1
```

### View All Container Logs with Timestamps
```bash
docker logs --timestamps moodle-web
```

### View Logs Since Specific Time
```bash
docker logs --since 2h moodle-web
```
Menampilkan logs 2 jam terakhir.

### Save Logs to File
```bash
docker logs moodle-web > moodle_logs.txt
```

### View Moodle Backup Logs
```bash
docker exec moodle-web tail -f /var/log/moodle-backup.log
```

### View Moodle Update Logs
```bash
docker exec moodle-web tail -f /var/log/moodle-updates.log
```

---

## Database Management

### Connect ke PostgreSQL via Command Line
```bash
docker exec -it moodle-pgdb psql -U moodleuser -d moodledatabase
```
Setelah login, gunakan command SQL:
```sql
\dt                    -- List all tables
SELECT version();      -- Check PostgreSQL version
\l                     -- List all databases
\du                    -- List all users
```

### Backup Database Manually
```bash
docker exec -i moodle-pgdb pg_dump -U moodleuser -d moodledatabase > backup_manual_$(date +%Y%m%d_%H%M%S).sql
```

### List All Backups
```bash
docker exec moodle-web ls -lah /var/www/moodledata/backups/
```

### View Backup Error Logs
```bash
docker exec moodle-web cat /var/www/moodledata/backups/backup_error.log
```

### Check PostgreSQL Disk Usage
```bash
docker exec moodle-pgdb du -sh /var/lib/postgresql/data
```

### Check Database Size
```bash
docker exec -it moodle-pgdb psql -U moodleuser -d moodledatabase -c "SELECT pg_size_pretty(pg_database_size('moodledatabase'));"
```

---

## Backup & Restore

### Run Backup Manually (Immediately)
```bash
docker exec moodle-web /usr/local/bin/moodle-backup.sh
```

### Check Last Backup Time
```bash
docker exec moodle-web ls -lt /var/www/moodledata/backups/ | head -1
```

### Restore Database from Backup
```bash
# Decompress backup jika masih .gz
docker exec moodle-web gunzip -c /var/www/moodledata/backups/backup_20260201_020000.sql.gz | docker exec -i moodle-pgdb psql -U moodleuser -d moodledatabase
```

### Restore Without Decompressing (jika .sql, bukan .gz)
```bash
docker exec -i moodle-pgdb psql -U moodleuser -d moodledatabase < /path/to/backup.sql
```

### Download Backup ke Local Machine
```bash
# Windows PowerShell
docker cp moodle-web:/var/www/moodledata/backups/backup_20260201_020000.sql.gz ./

# Copy semua backups
docker cp moodle-web:/var/www/moodledata/backups/ ./backups_downloaded/
```

### Check Cron Jobs Status
```bash
docker exec moodle-web crontab -u www-data -l
```

### Force Run Cron Job
```bash
docker exec moodle-web /usr/local/bin/moodle-backup.sh
docker exec moodle-web /usr/local/bin/watch-moodle-updates.sh
```

---

## File Management

### Enter Moodle Container Shell
```bash
docker exec -it moodle-web bash
```
Setelah masuk, Anda bisa:
```bash
cd /var/www/html        # Ke folder Moodle
ls -la                  # List files
cat config.php          # View config
ps aux                  # List processes
```

### Enter PostgreSQL Container Shell
```bash
docker exec -it moodle-pgdb sh
```

### Copy File dari Container ke Local
```bash
# Single file
docker cp moodle-web:/var/www/html/config.php ./config.php

# Entire directory
docker cp moodle-web:/var/www/html/theme/ ./theme_backup/
```

### Copy File dari Local ke Container
```bash
docker cp ./mytheme/ moodle-web:/var/www/html/theme/mytheme/
```

### View Moodle Directory Structure
```bash
docker exec moodle-web tree -L 2 /var/www/html/
```

### Check Disk Usage
```bash
docker exec moodle-web du -sh /var/www/html
docker exec moodle-web du -sh /var/www/moodledata
```

### List All Files in Moodledata
```bash
docker exec moodle-web find /var/www/moodledata -type f | head -20
```

### Change File Permissions
```bash
docker exec moodle-web chmod -R 755 /var/www/html/theme/mytheme/
```

### Change File Ownership
```bash
docker exec moodle-web chown -R www-data:www-data /var/www/html/local/
```

---

## Troubleshooting

### Check Container Health
```bash
docker-compose ps
```

### Inspect Container Details
```bash
docker inspect moodle-web
docker inspect moodle-pgdb
```

### Check Network Connectivity Between Containers
```bash
# Test dari Moodle ke PostgreSQL
docker exec moodle-web ping postgres

# Test DNS resolution
docker exec moodle-web nslookup postgres
```

### Test PostgreSQL Connection from Moodle
```bash
docker exec moodle-web pg_isready -h postgres -U moodleuser
```

### View Environment Variables di Container
```bash
docker exec moodle-web env | grep MOODLE
docker exec moodle-web env | grep PGSQL
```

### Check Apache Status
```bash
docker exec moodle-web systemctl status apache2
# atau
docker exec moodle-web service apache2 status
```

### Check Apache Error Logs
```bash
docker exec moodle-web tail -100 /var/log/apache2/error.log
docker exec moodle-web tail -100 /var/log/apache2/access.log
```

### Restart Apache Service
```bash
docker exec moodle-web service apache2 restart
```

### Check Cron Service
```bash
docker exec moodle-web service cron status
```

### Restart Cron Service
```bash
docker exec moodle-web service cron restart
```

### Validate config.php PHP Syntax
```bash
docker exec moodle-web php -l /var/www/html/config.php
```

### Check PHP Extensions
```bash
docker exec moodle-web php -m | grep -E "pgsql|mysqli|gd"
```

### Test Database Query
```bash
docker exec -it moodle-pgdb psql -U moodleuser -d moodledatabase -c "SELECT count(*) as table_count FROM information_schema.tables WHERE table_schema = 'public';"
```

### View Secret Files (Password)
```bash
cat ./secrets/db_password.txt
cat ./secrets/db_root_password.txt
```

---

## Cleanup & Reset

### Remove All Containers (Keep Volumes & Data)
```bash
docker-compose down
```

### Remove All Containers + Volumes (DELETE DATA - HATI-HATI!)
```bash
docker-compose down -v
```
⚠️ **WARNING**: Ini akan menghapus semua databases dan data!

### Remove Unused Volumes
```bash
docker volume prune
```

### Remove Unused Images
```bash
docker image prune -a
```

### Remove Specific Volume (HATI-HATI!)
```bash
docker volume rm moodle-docker_pgdata
docker volume rm moodle-docker_moodledata
docker volume rm moodle-docker_moodlefile
```

### Clean Up Old Backups (Keep Last 7 Days)
```bash
docker exec moodle-web find /var/www/moodledata/backups -name "backup_*.sql.gz" -mtime +7 -delete
```

### Remove Container & Rebuild Fresh
```bash
docker-compose down
docker-compose up -d --build
```

### Hard Reset Moodle (Delete All Data)
```bash
# ⚠️ HATI-HATI! Ini menghapus SEMUA
docker-compose down -v
docker volume rm moodle-docker_pgdata moodle-docker_moodledata moodle-docker_moodlefile
docker-compose up -d --build
```

### Remove Old Log Files
```bash
docker exec moodle-web rm -f /var/log/moodle-backup.log
docker exec moodle-web rm -f /var/log/moodle-updates.log
```

---

## 🚀 Quick Start Commands

### First Time Setup
```bash
# 1. Build image
docker-compose build

# 2. Start containers
docker-compose up -d

# 3. Wait 30 seconds for database to initialize
sleep 30

# 4. Check logs
docker logs -f moodle-web

# 5. Open browser
# Moodle: http://localhost
# pgAdmin: http://localhost:81
```

### Daily Development
```bash
# Start containers
docker-compose up -d

# View logs
docker logs -f moodle-web

# Work on files (auto-sync via volume)
# Edit ./moodle-custom/ files

# Check backups
docker exec moodle-web ls /var/www/moodledata/backups/

# Stop containers
docker-compose down
```

### Production Backup
```bash
# Manual backup
docker exec -i moodle-pgdb pg_dump -U moodleuser -d moodledatabase > backup_prod_$(date +%Y%m%d_%H%M%S).sql

# Compress
gzip backup_prod_*.sql

# Download to safe location
docker cp moodle-web:/var/www/moodledata/backups/ ./prod_backups/
```

---

## 📊 Monitoring Checklist

```bash
# Daily checks
docker-compose ps                              # Container status
docker logs --tail 50 moodle-web              # Recent logs
docker exec moodle-web ls /var/www/moodledata/backups/ | tail -3  # Recent backups
docker exec moodle-web du -sh /var/www/moodledata  # Data size

# Weekly checks
docker exec -it moodle-pgdb psql -U moodleuser -d moodledatabase -c "SELECT pg_size_pretty(pg_database_size('moodledatabase'));"
docker logs moodle-pgdb | grep ERROR

# Monthly checks
docker volume ls | grep moodle                # Check volumes
docker image ls | grep moodle                 # Check images
du -sh ./moodledata/                          # Check local storage
```

---

## 💡 Tips & Tricks

### Alias Commands (Linux/Mac)
```bash
# Add to ~/.bashrc or ~/.zshrc
alias moodle-start='docker-compose up -d'
alias moodle-stop='docker-compose down'
alias moodle-logs='docker logs -f moodle-web'
alias moodle-bash='docker exec -it moodle-web bash'
alias moodle-backup='docker exec moodle-web /usr/local/bin/moodle-backup.sh'
```

### Windows PowerShell Aliases
```powershell
# Add to $PROFILE
Set-Alias moodle-start 'docker-compose up -d'
Set-Alias moodle-stop 'docker-compose down'
Set-Alias moodle-logs 'docker logs -f moodle-web'
Set-Alias moodle-bash 'docker exec -it moodle-web bash'
```

### Monitor Multiple Logs
```bash
docker-compose logs -f
```
Shows logs dari semua containers sekaligus.

### Check Health Status
```bash
# Full status
docker-compose ps

# With additional info
docker stats

# Per container
docker exec moodle-web ps aux | grep apache
docker exec moodle-pgdb pg_isready -v
```

---

**Last Updated:** February 1, 2026
**Version:** 1.0