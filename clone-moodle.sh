#!/bin/bash
set -e

TARGET="moodle"

if [ -d "$TARGET" ]; then
  echo "Folder $TARGET sudah ada — skip clone"
else
  git clone --branch MOODLE_501_STABLE https://github.com/moodle/moodle.git "$TARGET"
fi
