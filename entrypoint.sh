#!/bin/bash

set -e

MOODLE_DIR=/var/www/html
MOODLE_CONFIG=$MOODLE_DIR/config.php
MOODLE_DATA=/var/www/moodledata

if [ ! -f "$MOODLE_CONFIG" ]; then
  echo "Generating Moodle config.php..."
  DB_PASS="$(cat "$MOODLE_DATABASE_PASSWORD_FILE")"

  cat > "$MOODLE_CONFIG" <<EOF
<?php
unset(\$CFG);
global \$CFG;
\$CFG = new stdClass();

\$CFG->dbtype    = 'pgsql';
\$CFG->dblibrary = 'native';
\$CFG->dbhost    = getenv('MOODLE_DATABASE_HOST') ?: 'postgres';
\$CFG->dbname    = getenv('MOODLE_DATABASE_NAME') ?: 'moodle';
\$CFG->dbuser    = getenv('MOODLE_DATABASE_USER') ?: 'moodleuser';
\$CFG->dbpass    = '${DB_PASS}';
\$CFG->prefix    = 'mdl_';

\$CFG->wwwroot   = getenv('MOODLE_WWWROOT') ?: 'http://localhost';
\$CFG->dataroot  = '$MOODLE_DATA';
\$CFG->admin     = 'admin';
\$CFG->sslproxy  = false;
\$CFG->directorypermissions = 0777;

require_once(__DIR__ . '/lib/setup.php');
EOF

  echo "Moodle config.php created."
else
  echo "Moodle config.php already exists — skipping generation."
fi

exec apache2-foreground