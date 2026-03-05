#!/bin/bash
# Generate moodle config.php with symbolic link by environment

set -e

# Detect environment
ENVIRONMENT=${ENVIRONMENT:-production}

MOODLE_DIR=/var/www/html
MOODLE_PUBLIC=$MOODLE_DIR/public
MOODLE_DATA=/var/www/moodledata

# Select config file
if [ "$ENVIRONMENT" = "development" ]; then
    MOODLE_CONFIG=$MOODLE_PUBLIC/config.dev.php
else
    MOODLE_CONFIG=$MOODLE_PUBLIC/config.prod.php
fi

echo "[$(date)] Config file: $MOODLE_CONFIG"

# Validate Moodle source
if [ ! -f "$MOODLE_PUBLIC/index.php" ]; then
    echo "[$(date)] ERROR: $MOODLE_PUBLIC/index.php not found"
    exit 1
fi

CONFIG_ROOT="$MOODLE_DIR/config.php"

# Skip only for production (prevent overwrite)
if [ "$ENVIRONMENT" = "production" ] && [ -f "$CONFIG_ROOT" ]; then
    echo "[$(date)] config.php already exists, skipping generation"
    exit 0
fi

###############################################
# Check existing config compatibility
###############################################

check_config() {

    local config_file=$1

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local config_host
    local config_user
    local config_name

    config_host=$(grep -oP "CFG->dbhost\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)
    config_user=$(grep -oP "CFG->dbuser\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)
    config_name=$(grep -oP "CFG->dbname\s*=\s*['\"]?\K[^'\";\s]*" "$config_file" 2>/dev/null | head -1)

    echo "[$(date)] Existing DB: HOST=$config_host USER=$config_user DB=$config_name"
    echo "[$(date)] Current  DB: HOST=$PGSQL_HOST USER=$PGSQL_USER DB=$PGSQL_DATABASE"

    if [ "$config_host" != "$PGSQL_HOST" ]; then return 0; fi
    if [ "$config_user" != "$PGSQL_USER" ]; then return 0; fi
    if [ "$config_name" != "$PGSQL_DATABASE" ]; then return 0; fi

    return 1
}

###############################################
# Resolve database password
###############################################

DB_PASS=""

if [ -f "$MOODLE_DATABASE_PASSWORD_FILE" ]; then
    DB_PASS=$(cat "$MOODLE_DATABASE_PASSWORD_FILE")
fi

if [ -z "$DB_PASS" ] && [ -n "$MOODLE_DATABASE_PASSWORD" ]; then
    DB_PASS="$MOODLE_DATABASE_PASSWORD"
fi

# CI fallback password
if [ -z "$DB_PASS" ]; then
    echo "[$(date)] WARNING: Using CI dummy database password"
    DB_PASS="ci-test-password"
fi

###############################################
# Environment specific settings
###############################################

if [ "$ENVIRONMENT" = "development" ]; then
    SSL_PROXY="false"
    DIR_PERMS="0777"
else
    SSL_PROXY="false"
    DIR_PERMS="0770"
fi

###############################################
# Generate config if needed
###############################################

if check_config "$MOODLE_CONFIG"; then

    echo "[$(date)] Generating config.php ($ENVIRONMENT)..."

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
\$CFG->dataroot = '${MOODLE_DATA}';
\$CFG->admin = 'admin';

\$CFG->sslproxy = ${SSL_PROXY};
\$CFG->directorypermissions = ${DIR_PERMS};

if ('${ENVIRONMENT}' === 'development') {
    \$CFG->debug = 32767;
    \$CFG->debugdisplay = true;
    \$CFG->perfdebug = 15;
} else {
    \$CFG->debug = 0;
    \$CFG->debugdisplay = false;
}

require_once(__DIR__ . '/../lib/setup.php');
EOF

    chmod 640 "$MOODLE_CONFIG"
    chown www-data:www-data "$MOODLE_CONFIG"

    ###############################################
    # Create symbolic links
    ###############################################

    rm -f "$MOODLE_PUBLIC/config.php"
    ln -s "$(basename "$MOODLE_CONFIG")" "$MOODLE_PUBLIC/config.php"

    rm -f "$MOODLE_DIR/config.php"
    ln -s "public/$(basename "$MOODLE_CONFIG")" "$MOODLE_DIR/config.php"

    echo "[$(date)] Config created: $MOODLE_CONFIG"

else

    echo "[$(date)] Config already valid, skipping generation"

fi
