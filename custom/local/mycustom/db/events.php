<?php
defined('MOODLE_INTERNAL') || die();

$observers = [
    [
        'eventname'   => '\core\event\plugin_installed',
        'callback'    => '\local_autobackup\observer::run_backup',
    ],
    [
        'eventname'   => '\core\event\plugin_updated',
        'callback'    => '\local_autobackup\observer::run_backup',
    ],
    [
        'eventname'   => '\core\event\plugin_uninstalled',
        'callback'    => '\local_autobackup\observer::run_backup',
    ],
    [
        'eventname'   => '\core\event\theme_updated',
        'callback'    => '\local_autobackup\observer::run_backup',
    ],
];