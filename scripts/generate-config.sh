#!/bin/bash
#generate moodle config.php with symbolic link by environment

set -e

#Detect environment

ENVIRONMENT=${ENVIRONMENT:-production}


MOODLE_DIR=/var/www/html
MOODLE_PUBLIC=$MOODLE_DIR/public
MOODLE_DATA=/var/www/moodledata


if [ "$ENVIRONMENT" = "development" ]; then
    MOODLE_CONFIG=$MOODLE_PUBLIC/config.dev.php
else
    MOODLE_CONFIG=$MOODLE_PUBLIC/config.prod.php
fi

echo "[$(date)] Config file: $MOODLE_CONFIG"

# Validate moodle source
if [ ! -f "$MOODLE_PUBLIC/index.php" ]; then
    echo "[$(date)] ERROR: $MOODLE_PUBLIC/index.php not found"
    exit 1
fi



check_config() {
    local config_file=$1
    [ ! -f "$config_file" ] && return 0

    local config_host=$(grep -oP "CFG->dbhost\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)
    local config_user=$(grep -oP "CFG->dbuser\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)
    local config_name=$(grep -oP "CFG->dbname\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)

    echo "[$(date)] Existing: HOST=$config_host,  USER=$config_user, DB=$config_name"
    echo "[$(date)] Current: HOST=$PGSQL_HOST, USER=$PGSQL_USER DB=$PGSQL_DATABASE"

    [ "$config_host" != "$PGSQL_HOST" ] && return 0
    [ "$config_user" != "$PGSQL_USER" ] && return 0
    [ "$config_name" != "$PGSQL_DATABASE" ] && return 0

    return 1

}

# Generate config if needed

if check_config "$MOODLE_CONFIG"; then
    echo "[$(date)] Generating config.php ($ENVIRONMENT)..."

    if [ -f "$MOODLE_DATABASE_PASSWORD_FILE" ]; then
        DB_PASS="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"
    else
        echo "[$(date)] ERROR: password file not found"
        exit 1
    fi


    if [ "$ENVIRONMENT" = "development" ]; then
        SSL_PROXY="false"
        DIR_PERMS="0777"
        DEBUGCFG=1
    else
        SSL_PROXY="false"
        DIR_PERMS="0770"
        DEBUGCFG=0
    fi

cat > "$MOODLE_CONFIG" <<EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype = 'pgsql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost = '${PGSQL_HOST}';
\$CFG->dbuser = '${PGSQL_USER}';
\$CFG->dbname = '${PGSQL_DATABASE}';
\$CFG->dbpass = '${DB_PASS}';
\$CFG->prefix = 'mdl_';

\$CFG->wwwroot = '${MOODLE_WWWROOT:-http://localhost:8080}';
\$CFG->dataroot = '$MOODLE_DATA';
\$CFG->admin = 'admin';
\$CFG->sslproxy = ${SSL_PROXY};
\$CFG->directorypermissions = ${DIR_PERMS};

if ('$ENVIRONMENT' === 'development') {
    \$CFG->debug = 32767;
    \$CFG->debugdisplay = true;

}else {
    \$CFG->debug= 0;
    \$CFG->debugdisplay = false;
}

require_once(__DIR__ . '/../lib/setup.php');
EOF

    chmod 640 "$MOODLE_CONFIG"
    chown www-data:www-data "$MOODLE_CONFIG"

    #symbolic link config.php -> config.{env}.php

    rm -f "$MOODLE_PUBLIC/config.php"
    ln -s "$(basename "$MOODLE_CONFIG")" "$MOODLE_PUBLIC/config.php"
    
    echo "[$(date)] Config Created: $MOODLE_CONFIG"
else
    echo "[$(date)] Config Already exist - Skip"

fi