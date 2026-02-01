<?php
namespace local_autobackup;

defined('MOODLE_INTERNAL') || die();

class observer {
    public static function run_backup($event) {
        // Path ke script backup Anda
        $cmd = '/usr/local/bin/moodle-backup.sh';

        // Set environment variable jika perlu (opsional, biasanya sudah diatur di container)
        putenv('MOODLE_DATABASE_HOST=' . getenv('MOODLE_DATABASE_HOST'));
        putenv('MOODLE_DATABASE_USER=' . getenv('MOODLE_DATABASE_USER'));
        putenv('MOODLE_DATABASE_NAME=' . getenv('MOODLE_DATABASE_NAME'));
        putenv('PGPASSWORD=' . getenv('PGPASSWORD'));

        // Jalankan backup di background
        exec("bash $cmd > /dev/null 2>&1 &");

        return true;
    }
}