<?php

declare(strict_types=1);

/**
 * Housekeeping for cron (hourly is plenty):
 *
 *   php tools/cleanup.php
 *
 * Removes expired tokens, stale rate-limit buckets, old idempotency keys and
 * audit rows past the retention window.
 */

use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Security\RateLimiter;
use OceanCast\Security\TokenService;

require dirname(__DIR__) . '/src/bootstrap.php';

$tokens = TokenService::purgeExpired();
RateLimiter::purgeExpired();

$idempotency = Database::run(
    'DELETE FROM idempotency_keys WHERE created_at < :cutoff',
    ['cutoff' => gmdate('Y-m-d H:i:s.u', time() - 86400)]
)->rowCount();

$retentionDays = Config::int('AUDIT_RETENTION_DAYS', 180);
$events = Database::run(
    'DELETE FROM security_events WHERE created_at < :cutoff',
    ['cutoff' => gmdate('Y-m-d H:i:s.u', time() - $retentionDays * 86400)]
)->rowCount();

fwrite(STDOUT, sprintf(
    "Cleaned: %d token(s), %d idempotency key(s), %d audit row(s).\n",
    $tokens,
    $idempotency,
    $events
));
