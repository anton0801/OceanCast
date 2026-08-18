<?php

declare(strict_types=1);

namespace OceanCast\Security;

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Core\Uuid;

/**
 * Opaque bearer tokens.
 *
 *  * 256 bits of entropy from the CSPRNG — not guessable, not derivable.
 *  * Only SHA-256 hashes are stored, so a leaked database cannot be replayed.
 *  * Short-lived access token + rotating refresh token.
 *  * Reusing an already-rotated refresh token revokes the whole family: a stolen
 *    token stops working as soon as the real device refreshes (or vice versa),
 *    and the theft is visible in the audit log.
 */
final class TokenService
{
    public const ACCESS_PREFIX  = 'sb_at_';
    public const REFRESH_PREFIX = 'sb_rt_';

    /**
     * @return array{accessToken:string,refreshToken:string,expiresIn:int,refreshExpiresIn:int,session:array<string,mixed>}
     */
    public static function issue(
        int $userId,
        string $deviceName,
        string $platform,
        string $ip,
        ?string $userAgent,
        ?string $familyId = null,
    ): array {
        $accessTtl = Config::int('ACCESS_TOKEN_TTL', 3600);
        $refreshTtl = Config::int('REFRESH_TOKEN_TTL', 2592000);

        $access = self::ACCESS_PREFIX . bin2hex(random_bytes(32));
        $refresh = self::REFRESH_PREFIX . bin2hex(random_bytes(32));
        $uuid = Uuid::v4();
        $now = time();

        Database::run(
            'INSERT INTO auth_tokens
                (uuid, user_id, family_id, access_hash, refresh_hash, device_name, platform, ip_hash,
                 user_agent, access_expires_at, refresh_expires_at, last_used_at, created_at)
             VALUES
                (:uuid, :user_id, :family_id, :access_hash, :refresh_hash, :device_name, :platform, :ip_hash,
                 :user_agent, :access_expires_at, :refresh_expires_at, :last_used_at, :created_at)',
            [
                'uuid'               => $uuid,
                'user_id'            => $userId,
                'family_id'          => $familyId ?? Uuid::v4(),
                'access_hash'        => self::hash($access),
                'refresh_hash'       => self::hash($refresh),
                'device_name'        => mb_substr($deviceName, 0, 120),
                'platform'           => mb_substr($platform, 0, 40),
                'ip_hash'            => AuditLog::hashIp($ip),
                'user_agent'         => $userAgent === null ? null : mb_substr($userAgent, 0, 255),
                'access_expires_at'  => gmdate('Y-m-d H:i:s.u', $now + $accessTtl),
                'refresh_expires_at' => gmdate('Y-m-d H:i:s.u', $now + $refreshTtl),
                'last_used_at'       => gmdate('Y-m-d H:i:s.u', $now),
                'created_at'         => gmdate('Y-m-d H:i:s.u', $now),
            ]
        );

        return [
            'accessToken'      => $access,
            'refreshToken'     => $refresh,
            'expiresIn'        => $accessTtl,
            'refreshExpiresIn' => $refreshTtl,
            'session'          => [
                'id'         => $uuid,
                'deviceName' => $deviceName,
                'platform'   => $platform,
                'createdAt'  => gmdate('c', $now),
                'current'    => true,
            ],
        ];
    }

    /**
     * Resolves a bearer token to its user. Throws with a distinct error code for
     * "expired" so the client knows to refresh instead of asking for a password.
     *
     * @return array{user:array<string,mixed>,token:array<string,mixed>}
     */
    public static function authenticate(string $rawToken): array
    {
        if (!str_starts_with($rawToken, self::ACCESS_PREFIX)) {
            throw ApiException::unauthorized('This token is not valid.', 'invalid_token');
        }

        $row = Database::first(
            'SELECT t.*, u.id AS u_id, u.uuid AS u_uuid, u.email, u.display_name, u.status,
                    u.created_at AS u_created_at, u.password_changed_at, u.deleted_at AS u_deleted_at
               FROM auth_tokens t
               JOIN users u ON u.id = t.user_id
              WHERE t.access_hash = :hash
              LIMIT 1',
            ['hash' => self::hash($rawToken)]
        );

        if ($row === null) {
            throw ApiException::unauthorized('This token is not valid.', 'invalid_token');
        }
        if ($row['revoked_at'] !== null) {
            throw ApiException::unauthorized('This session was signed out.', 'token_revoked');
        }
        if ($row['status'] !== 'active' || $row['u_deleted_at'] !== null) {
            throw ApiException::unauthorized('This account is no longer active.', 'account_inactive');
        }
        if (strtotime((string) $row['access_expires_at']) < time()) {
            throw ApiException::unauthorized('This access token has expired.', 'token_expired');
        }

        // Keep session listings useful without writing on every single request.
        if ($row['last_used_at'] === null || strtotime((string) $row['last_used_at']) < time() - 60) {
            Database::run(
                'UPDATE auth_tokens SET last_used_at = :now WHERE id = :id',
                ['now' => gmdate('Y-m-d H:i:s.u'), 'id' => (int) $row['id']]
            );
        }

        return [
            'user' => [
                'id'          => (int) $row['u_id'],
                'uuid'        => (string) $row['u_uuid'],
                'email'       => (string) $row['email'],
                'displayName' => (string) $row['display_name'],
                'createdAt'   => (string) $row['u_created_at'],
            ],
            'token' => [
                'id'        => (int) $row['id'],
                'uuid'      => (string) $row['uuid'],
                'familyId'  => (string) $row['family_id'],
                'device'    => (string) $row['device_name'],
            ],
        ];
    }

    /**
     * @return array{accessToken:string,refreshToken:string,expiresIn:int,refreshExpiresIn:int,session:array<string,mixed>,userId:int}
     */
    public static function refresh(string $rawRefresh, string $ip, ?string $userAgent): array
    {
        if (!str_starts_with($rawRefresh, self::REFRESH_PREFIX)) {
            throw ApiException::unauthorized('This refresh token is not valid.', 'invalid_token');
        }

        $outcome = Database::transaction(static function () use ($rawRefresh, $ip, $userAgent): array {
            $row = Database::first(
                'SELECT t.*, u.status FROM auth_tokens t
                   JOIN users u ON u.id = t.user_id
                  WHERE t.refresh_hash = :hash
                  LIMIT 1
                    FOR UPDATE',
                ['hash' => self::hash($rawRefresh)]
            );

            if ($row === null) {
                throw ApiException::unauthorized('This refresh token is not valid.', 'invalid_token');
            }

            $userId = (int) $row['user_id'];

            // Replay of an already-rotated token: assume theft. The revocation
            // happens after this transaction commits — throwing from inside it
            // would roll the revocation back with everything else.
            if ($row['rotated_at'] !== null) {
                return ['reuseFamily' => (string) $row['family_id'], 'userId' => $userId];
            }
            if ($row['revoked_at'] !== null) {
                throw ApiException::unauthorized('This session was signed out.', 'token_revoked');
            }
            if ($row['status'] !== 'active') {
                throw ApiException::unauthorized('This account is no longer active.', 'account_inactive');
            }
            if (strtotime((string) $row['refresh_expires_at']) < time()) {
                throw ApiException::unauthorized('This session expired. Sign in again.', 'refresh_expired');
            }

            Database::run(
                'UPDATE auth_tokens
                    SET rotated_at = :rotated_at, revoked_at = :revoked_at, revoked_reason = :reason
                  WHERE id = :id',
                [
                    'rotated_at' => gmdate('Y-m-d H:i:s.u'),
                    'revoked_at' => gmdate('Y-m-d H:i:s.u'),
                    'reason'     => 'rotated',
                    'id'         => (int) $row['id'],
                ]
            );

            $issued = self::issue(
                $userId,
                (string) $row['device_name'],
                (string) $row['platform'],
                $ip,
                $userAgent,
                (string) $row['family_id'],
            );
            $issued['userId'] = $userId;
            return $issued;
        });

        if (isset($outcome['reuseFamily'])) {
            self::revokeFamily((string) $outcome['reuseFamily'], 'refresh_reuse');
            AuditLog::record((int) $outcome['userId'], 'refresh_token_reuse', 'family ' . $outcome['reuseFamily'], $ip);
            throw ApiException::unauthorized(
                'This session was ended for security reasons. Sign in again.',
                'token_reuse_detected'
            );
        }

        return $outcome;
    }

    public static function revokeById(int $tokenId, string $reason): void
    {
        Database::run(
            'UPDATE auth_tokens SET revoked_at = :now, revoked_reason = :reason
              WHERE id = :id AND revoked_at IS NULL',
            ['now' => gmdate('Y-m-d H:i:s.u'), 'reason' => $reason, 'id' => $tokenId]
        );
    }

    public static function revokeByUuid(int $userId, string $uuid, string $reason): bool
    {
        $statement = Database::run(
            'UPDATE auth_tokens SET revoked_at = :now, revoked_reason = :reason
              WHERE user_id = :user_id AND uuid = :uuid AND revoked_at IS NULL',
            [
                'now'     => gmdate('Y-m-d H:i:s.u'),
                'reason'  => $reason,
                'user_id' => $userId,
                'uuid'    => Uuid::normalize($uuid),
            ]
        );
        return $statement->rowCount() > 0;
    }

    public static function revokeFamily(string $familyId, string $reason): void
    {
        Database::run(
            'UPDATE auth_tokens SET revoked_at = :now, revoked_reason = :reason
              WHERE family_id = :family AND revoked_at IS NULL',
            ['now' => gmdate('Y-m-d H:i:s.u'), 'reason' => $reason, 'family' => $familyId]
        );
    }

    public static function revokeAllForUser(int $userId, string $reason, ?int $exceptTokenId = null): int
    {
        $sql = 'UPDATE auth_tokens SET revoked_at = :now, revoked_reason = :reason
                 WHERE user_id = :user_id AND revoked_at IS NULL';
        $params = ['now' => gmdate('Y-m-d H:i:s.u'), 'reason' => $reason, 'user_id' => $userId];
        if ($exceptTokenId !== null) {
            $sql .= ' AND id <> :except';
            $params['except'] = $exceptTokenId;
        }
        return Database::run($sql, $params)->rowCount();
    }

    /** @return array<int,array<string,mixed>> */
    public static function sessions(int $userId, int $currentTokenId): array
    {
        $rows = Database::all(
            'SELECT id, uuid, device_name, platform, created_at, last_used_at, access_expires_at, refresh_expires_at
               FROM auth_tokens
              WHERE user_id = :user_id AND revoked_at IS NULL AND refresh_expires_at > :now
              ORDER BY last_used_at DESC',
            ['user_id' => $userId, 'now' => gmdate('Y-m-d H:i:s.u')]
        );

        return array_map(static fn (array $row): array => [
            'id'         => (string) $row['uuid'],
            'deviceName' => (string) $row['device_name'],
            'platform'   => (string) $row['platform'],
            'createdAt'  => gmdate('c', strtotime((string) $row['created_at'])),
            'lastUsedAt' => $row['last_used_at'] === null ? null : gmdate('c', strtotime((string) $row['last_used_at'])),
            'expiresAt'  => gmdate('c', strtotime((string) $row['refresh_expires_at'])),
            'current'    => (int) $row['id'] === $currentTokenId,
        ], $rows);
    }

    public static function purgeExpired(): int
    {
        return Database::run(
            'DELETE FROM auth_tokens
              WHERE refresh_expires_at < :cutoff
                 OR (revoked_at IS NOT NULL AND revoked_at < :cutoff)',
            ['cutoff' => gmdate('Y-m-d H:i:s.u', time() - 7 * 86400)]
        )->rowCount();
    }

    private static function hash(string $raw): string
    {
        return hash('sha256', $raw);
    }
}
