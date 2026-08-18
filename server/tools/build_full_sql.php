<?php

declare(strict_types=1);

/**
 * Builds database/oceancast_full.sql from the migrations, so the one-file
 * import that shared hosting needs can never drift away from the schema the
 * migration tool applies.
 *
 *   php tools/build_full_sql.php
 */

$root = dirname(__DIR__);
$files = glob($root . '/migrations/*.sql') ?: [];
sort($files);

if ($files === []) {
    fwrite(STDERR, "No migrations found.\n");
    exit(1);
}

$body = '';
$tables = [];
foreach ($files as $file) {
    $sql = (string) file_get_contents($file);
    $body .= "\n-- ==== " . basename($file) . " " . str_repeat('=', max(0, 60 - strlen(basename($file)))) . "\n\n";
    $body .= trim($sql) . "\n";

    if (preg_match_all('/CREATE TABLE IF NOT EXISTS\s+(\w+)/i', $sql, $matches)) {
        $tables = array_merge($tables, $matches[1]);
    }
}
$tables[] = 'schema_migrations';
$tables = array_values(array_unique($tables));

$dropList = implode("\n", array_map(
    static fn (string $table): string => '--     DROP TABLE IF EXISTS `' . $table . '`;',
    $tables
));

$applied = implode("\n", array_map(
    static fn (string $file): string => "    ('" . basename($file) . "', UTC_TIMESTAMP(6)),",
    $files
));
$applied = rtrim($applied, ',');

$header = <<<SQL
-- ============================================================================
--  Ocean Cast — complete database setup (one file)
-- ============================================================================
--
--  Generated from server/migrations/*.sql by tools/build_full_sql.php.
--  Do not edit by hand: change the migration and regenerate.
--
--  HOW TO USE ON SHARED HOSTING (Hostinger, cPanel, ISPmanager …)
--    1. Control panel -> Databases -> MySQL: create a database and a user,
--       and give that user every privilege on the database.
--    2. Open phpMyAdmin, SELECT THAT DATABASE in the left column,
--       then Import -> choose this file -> Go.
--    3. Put the same database name, user and password into .env
--       (DB_NAME / DB_USER / DB_PASSWORD, DB_HOST is usually localhost).
--
--  This file deliberately does NOT contain CREATE DATABASE or USE: shared
--  hosting creates the database for you, often with a prefixed name, and the
--  import runs inside the database you selected.
--
--  Running it twice is safe — every table uses CREATE TABLE IF NOT EXISTS.
--
--  Requires MySQL 8.0+ or MariaDB 10.6+ (utf8mb4, JSON columns, DATETIME(6)).
--  On MariaDB replace utf8mb4_0900_ai_ci with utf8mb4_uca1400_ai_ci or
--  utf8mb4_general_ci if the import complains about the collation.
-- ----------------------------------------------------------------------------

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION';

-- --- OPTIONAL CLEAN RESET ----------------------------------------------------
-- Uncomment this block to wipe every Ocean Cast table before importing.
-- IT DELETES ALL ACCOUNTS AND ALL KITCHEN DATA.
--
--     SET FOREIGN_KEY_CHECKS = 0;
{$dropList}
--     SET FOREIGN_KEY_CHECKS = 1;
-- -----------------------------------------------------------------------------

SQL;

$footer = <<<SQL


-- ==== migration bookkeeping =================================================
-- Lets tools/migrate.php know the schema is already in place, so a later
-- deployment applies only NEW migrations.

CREATE TABLE IF NOT EXISTS schema_migrations (
    name       VARCHAR(190) NOT NULL PRIMARY KEY,
    applied_at DATETIME(6)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO schema_migrations (name, applied_at) VALUES
{$applied};

-- ==== verification ==========================================================
-- After the import this should list 21 tables.

SELECT TABLE_NAME AS created_table
  FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = DATABASE()
 ORDER BY TABLE_NAME;

SQL;

$path = $root . '/database/oceancast_full.sql';
file_put_contents($path, $header . $body . $footer);

fwrite(STDOUT, "Wrote " . $path . "\n");
fwrite(STDOUT, count($tables) . " table(s), " . count($files) . " migration(s).\n");
