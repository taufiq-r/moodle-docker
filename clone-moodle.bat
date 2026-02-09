@echo off 
:: turns off command echoing, only output to shown

setlocal
:: start a local environment variable, so dont affect global environment

set TARGET=moodle
:: set a variable called TARGET with the value "moodle"

if exist "%TARGET\" (
    echo Folder %TARGET% already exists, skipping clone
) else (
    git clone --branch MOODLE_501_STABLE https://github.com/moodle/moodle.git "%TARGET%"
) 
:: if folder "moodle" already exist, skip cloning
:: it folder "moodle" doesn't exist start cloning


endlocal
:: end local environment, cleanup temporary variable

