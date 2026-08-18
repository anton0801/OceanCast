<?php

declare(strict_types=1);

namespace OceanCast\Security;

use OceanCast\Core\Config;
use OceanCast\Core\Database;

/**
 * Append-only trail of security-relevant events. Raw IPs and tokens are never
 * written — only keyed hashes, so the log itself is not a liability.
 */
final class AuditLog
{
    public static function record(?int $userId, string $event, ?string $detail = null, ?string $ip = null): void
    {
        try {
            Database::run(
                'INSERT INTO security_events (user_id, event, detail, ip_hash, created_at)
                 VALUES (:user_id, :event, :detail, :ip_hash, :created_at)',
                [
                    'user_id'    => $userId,
                    'event'      => substr($event, 0, 60),
                    'detail'     => $detail === null ? null : substr($detail, 0, 255),
                    'ip_hash'    => $ip === null ? null : self::hashIp($ip),
                    'created_at' => gmdate('Y-m-d H:i:s.u'),
                ]
            );
        } catch (\Throwable) {
            // Never let audit logging break a request.
        }
    }

    public static function hashIp(string $ip): string
    {
        return hash_hmac('sha256', $ip, Config::string('APP_KEY'));
    }
}
