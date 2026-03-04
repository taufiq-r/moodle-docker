@echo off
setlocal

set TARGET=src

if exist "%TARGET%" (
    echo Folder %TARGET% already exists, skipping clone
) else (
    git config --global core.autocrlf false
    git clone --branch MOODLE_501_STABLE https://github.com/moodle/moodle.git "%TARGET%"
)

endlocal