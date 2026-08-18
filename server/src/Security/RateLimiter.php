<?php

declare(strict_types=1);

namespace OceanCast\Security;

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;

/**
 * Fixed-window counters in MySQL. Cheap, shared across workers, and good enough
 * to make online password guessing pointless.
 */
final class RateLimiter
{
    public static function hit(string $scope, string $identity, int $limit, int $windowSeconds): void
    {
        $bucket = hash_hmac('sha256', $scope . '|' . $identity, Config::string('APP_KEY'));
        $now = time();

        Database::transaction(static function () use ($bucket, $limit, $windowSeconds, $now): void {
            $row = Database::first(
                'SELECT hits, UNIX_TIMESTAMP(window_start) AS started
                   FROM rate_limits WHERE bucket = :bucket FOR UPDATE',
                ['bucket' => $bucket]
            );

            if ($row === null) {
                Database::run(
                    'INSERT INTO rate_limits (bucket, hits, window_start)
                     VALUES (:bucket, 1, :start)
                     ON DUPLICATE KEY UPDATE hits = hits + 1',
                    ['bucket' => $bucket, 'start' => gmdate('Y-m-d H:i:s', $now)]
                );
                return;
            }

            $started = (int) $row['started'];
            $hits = (int) $row['hits'];

            if ($now - $started >= $windowSeconds) {
                Database::run(
                    'UPDATE rate_limits SET hits = 1, window_start = :start WHERE bucket = :bucket',
                    ['bucket' => $bucket, 'start' => gmdate('Y-m-d H:i:s', $now)]
                );
                return;
            }

            if ($hits >= $limit) {
                throw ApiException::tooManyRequests(
                    'Too many attempts. Wait a moment and try again.',
                    $windowSeconds - ($now - $started)
                );
            }

            Database::run(
                'UPDATE rate_limits SET hits = hits + 1 WHERE bucket = :bucket',
                ['bucket' => $bucket]
            );
        });
    }

    public static function clear(string $scope, string $identity): void
    {
        $bucket = hash_hmac('sha256', $scope . '|' . $identity, Config::string('APP_KEY'));
        Database::run('DELETE FROM rate_limits WHERE bucket = :bucket', ['bucket' => $bucket]);
    }

    /** Housekeeping for a cron job. */
    public static function purgeExpired(int $olderThanSeconds = 86400): void
    {
        Database::run(
            'DELETE FROM rate_limits WHERE window_start < :cutoff',
            ['cutoff' => gmdate('Y-m-d H:i:s', time() - $olderThanSeconds)]
        );
    }
}
