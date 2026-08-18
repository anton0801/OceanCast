<?php

declare(strict_types=1);

/**
 * Applies every .sql file in migrations/ that has not run yet.
 *
 *   php tools/migrate.php            apply pending migrations
 *   php tools/migrate.php --status   show what would run
 */

use OceanCast\Core\Config;
use OceanCast\Core\Database;

require dirname(__DIR__) . '/src/bootstrap.php';

$statusOnly = in_array('--status', $argv ?? [], true);

Database::run(
    'CREATE TABLE IF NOT EXISTS schema_migrations (
        name VARCHAR(190) NOT NULL PRIMARY KEY,
        applied_at DATETIME(6) NOT NULL
     ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
);

$applied = array_column(Database::all('SELECT name FROM schema_migrations'), 'name');
$files = glob(dirname(__DIR__) . '/migrations/*.sql') ?: [];
sort($files);

$pending = array_values(array_filter(
    $files,
    static fn (string $file): bool => !in_array(basename($file), $applied, true)
));

if ($pending === []) {
    fwrite(STDOUT, "Database is up to date (" . count($applied) . " migration(s) applied).\n");
    exit(0);
}

fwrite(STDOUT, "Pending:\n");
foreach ($pending as $file) {
    fwrite(STDOUT, '  - ' . basename($file) . "\n");
}

if ($statusOnly) {
    exit(0);
}

foreach ($pending as $file) {
    $sql = (string) file_get_contents($file);
    fwrite(STDOUT, 'Applying ' . basename($file) . ' … ');

    // Split on semicolons at end of line; the schema has no stored routines.
    $statements = array_filter(
        array_map('trim', preg_split('/;\s*$/m', $sql) ?: []),
        static fn (string $statement): bool => $statement !== ''
    );

    // DDL commits implicitly in MySQL, so a transaction here would be a lie.
    // Every statement in the schema is written to be re-runnable instead.
    try {
        foreach ($statements as $statement) {
            Database::pdo()->exec($statement);
        }
        Database::run(
            'INSERT INTO schema_migrations (name, applied_at) VALUES (:name, :now)',
            ['name' => basename($file), 'now' => gmdate('Y-m-d H:i:s.u')]
        );
        fwrite(STDOUT, "ok\n");
    } catch (Throwable $error) {
        fwrite(STDERR, "failed\n  " . $error->getMessage() . "\n");
        fwrite(STDERR, "  The schema uses CREATE TABLE IF NOT EXISTS, so it is safe to fix and re-run.\n");
        exit(1);
    }
}

fwrite(STDOUT, "Done. Environment: " . Config::string('APP_ENV', 'production') . "\n");
