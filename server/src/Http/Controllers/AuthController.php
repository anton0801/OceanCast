<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Core\Uuid;
use OceanCast\Core\Validator;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Http\Auth;
use OceanCast\Security\AuditLog;
use OceanCast\Security\Passwords;
use OceanCast\Security\RateLimiter;
use OceanCast\Security\TokenService;

final class AuthController
{
    private const MAX_FAILED_LOGINS = 8;
    private const LOCK_MINUTES = 15;

    public function register(Request $request): Response
    {
        RateLimiter::hit('register:ip', $request->ip, Config::int('RATE_REGISTER_PER_HOUR', 5), 3600);

        $input = $request->json();
        $data = (new Validator($input))
            ->email('email')
            ->password('password')
            ->string('displayName', true, 1, 100)
            ->validated();

        $emailHash = self::emailHash($data['email']);
        $now = ResourceRepository::now();

        $existing = Database::first('SELECT id FROM users WHERE email = :email LIMIT 1', ['email' => $data['email']]);
        if ($existing !== null) {
            // Do not confirm which addresses are registered.
            AuditLog::record(null, 'register_duplicate', null, $request->ip);
            throw ApiException::conflict(
                'This email cannot be used for a new account. If it is yours, sign in or reset your password.',
                'email_unavailable'
            );
        }

        $uuid = Uuid::v4();
        Database::run(
            // Native prepared statements bind by position, so each placeholder
            // gets its own name even when the value repeats.
            'INSERT INTO users (uuid, email, email_hash, password_hash, display_name, status,
                                password_changed_at, created_at, updated_at)
             VALUES (:uuid, :email, :email_hash, :password_hash, :display_name, :status,
                     :password_changed_at, :created_at, :updated_at)',
            [
                'uuid'                => $uuid,
                'email'               => $data['email'],
                'email_hash'          => $emailHash,
                'password_hash'       => Passwords::hash($data['password']),
                'display_name'        => $data['displayName'],
                'status'              => 'active',
                'password_changed_at' => $now,
                'created_at'          => $now,
                'updated_at'          => $now,
            ]
        );

        $userId = (int) Database::pdo()->lastInsertId();
        AuditLog::record($userId, 'register', null, $request->ip);

        $tokens = TokenService::issue(
            $userId,
            self::deviceName($request),
            self::platform($request),
            $request->ip,
            $request->header('user-agent'),
        );

        return Response::created([
            'user' => [
                'id'          => $uuid,
                'email'       => $data['email'],
                'displayName' => $data['displayName'],
                'createdAt'   => ResourceRepository::iso($now),
            ],
            'auth' => self::authPayload($tokens),
        ]);
    }

    public function login(Request $request): Response
    {
        RateLimiter::hit('login:ip', $request->ip, Config::int('RATE_LOGIN_PER_IP', 20), 900);

        $input = $request->json();
        $data = (new Validator($input))
            ->email('email')
            ->string('password', true, 1, 200)
            ->validated();

        RateLimiter::hit('login:email', self::emailHash($data['email']), Config::int('RATE_LOGIN_PER_EMAIL', 8), 900);

        $user = Database::first(
            'SELECT * FROM users WHERE email = :email LIMIT 1',
            ['email' => $data['email']]
        );

        if ($user === null) {
            Passwords::burnTime();
            AuditLog::record(null, 'login_unknown_email', null, $request->ip);
            throw ApiException::unauthorized('Email or password is incorrect.', 'invalid_credentials');
        }

        $userId = (int) $user['id'];

        if ($user['status'] === 'deleted' || $user['deleted_at'] !== null) {
            Passwords::burnTime();
            throw ApiException::unauthorized('Email or password is incorrect.', 'invalid_credentials');
        }
        if ($user['locked_until'] !== null && strtotime((string) $user['locked_until']) > time()) {
            $seconds = strtotime((string) $user['locked_until']) - time();
            AuditLog::record($userId, 'login_locked', null, $request->ip);
            throw ApiException::tooManyRequests(
                'Too many failed attempts. This account is paused for ' . ceil($seconds / 60) . ' minute(s).',
                $seconds
            );
        }

        if (!Passwords::verify($data['password'], (string) $user['password_hash'])) {
            $failed = (int) $user['failed_logins'] + 1;
            $lockUntil = $failed >= self::MAX_FAILED_LOGINS
                ? gmdate('Y-m-d H:i:s.u', time() + self::LOCK_MINUTES * 60)
                : null;

            Database::run(
                'UPDATE users SET failed_logins = :failed, locked_until = :lock, updated_at = :now WHERE id = :id',
                ['failed' => $failed, 'lock' => $lockUntil, 'now' => ResourceRepository::now(), 'id' => $userId]
            );
            AuditLog::record($userId, 'login_failed', 'attempt ' . $failed, $request->ip);
            throw ApiException::unauthorized('Email or password is incorrect.', 'invalid_credentials');
        }

        // Successful login: clear the counters and upgrade the hash if needed.
        $updates = [
            'failed_logins' => 0,
            'locked_until'  => null,
            'last_login_at' => ResourceRepository::now(),
            'now'           => ResourceRepository::now(),
            'id'            => $userId,
        ];
        $sql = 'UPDATE users SET failed_logins = :failed_logins, locked_until = :locked_until,
                       last_login_at = :last_login_at, updated_at = :now';
        if (Passwords::needsRehash((string) $user['password_hash'])) {
            $sql .= ', password_hash = :password_hash';
            $updates['password_hash'] = Passwords::hash($data['password']);
        }
        $sql .= ' WHERE id = :id';
        Database::run($sql, $updates);

        RateLimiter::clear('login:email', self::emailHash($data['email']));
        AuditLog::record($userId, 'login', null, $request->ip);

        $tokens = TokenService::issue(
            $userId,
            self::deviceName($request),
            self::platform($request),
            $request->ip,
            $request->header('user-agent'),
        );

        return Response::ok([
            'user' => [
                'id'          => (string) $user['uuid'],
                'email'       => (string) $user['email'],
                'displayName' => (string) $user['display_name'],
                'createdAt'   => ResourceRepository::iso((string) $user['created_at']),
            ],
            'auth' => self::authPayload($tokens),
        ]);
    }

    public function refresh(Request $request): Response
    {
        RateLimiter::hit('refresh:ip', $request->ip, Config::int('RATE_REFRESH_PER_HOUR', 120), 3600);

        $data = (new Validator($request->json()))
            ->string('refreshToken', true, 20, 200)
            ->validated();

        $tokens = TokenService::refresh($data['refreshToken'], $request->ip, $request->header('user-agent'));
        AuditLog::record((int) $tokens['userId'], 'token_refresh', null, $request->ip);

        return Response::ok(['auth' => self::authPayload($tokens)]);
    }

    public function logout(Request $request, Auth $auth): Response
    {
        TokenService::revokeById($auth->tokenId(), 'logout');
        AuditLog::record($auth->userId(), 'logout', null, $request->ip);
        return Response::ok(['status' => 'signed_out']);
    }

    public function logoutAll(Request $request, Auth $auth): Response
    {
        $count = TokenService::revokeAllForUser($auth->userId(), 'logout_all');
        AuditLog::record($auth->userId(), 'logout_all', $count . ' session(s)', $request->ip);
        return Response::ok(['status' => 'signed_out_everywhere', 'revokedSessions' => $count]);
    }

    public function sessions(Request $request, Auth $auth): Response
    {
        return Response::ok(['sessions' => TokenService::sessions($auth->userId(), $auth->tokenId())]);
    }

    /** @param array<string,string> $params */
    public function revokeSession(Request $request, Auth $auth, array $params): Response
    {
        $uuid = $params['id'] ?? '';
        if (!Uuid::isValid($uuid)) {
            throw ApiException::validation('Some fields need attention.', ['id' => 'This must be a UUID.']);
        }
        if (!TokenService::revokeByUuid($auth->userId(), $uuid, 'revoked_by_user')) {
            throw ApiException::notFound('That session is not active.');
        }
        AuditLog::record($auth->userId(), 'session_revoked', null, $request->ip);
        return Response::ok(['status' => 'revoked']);
    }

    // ------------------------------------------------------------- helpers

    /** @param array<string,mixed> $tokens */
    public static function authPayload(array $tokens): array
    {
        return [
            'accessToken'      => $tokens['accessToken'],
            'refreshToken'     => $tokens['refreshToken'],
            'tokenType'        => 'Bearer',
            'expiresIn'        => $tokens['expiresIn'],
            'refreshExpiresIn' => $tokens['refreshExpiresIn'],
            'session'          => $tokens['session'],
        ];
    }

    public static function emailHash(string $email): string
    {
        return hash_hmac('sha256', strtolower($email), Config::string('APP_KEY'));
    }

    private static function deviceName(Request $request): string
    {
        $name = trim((string) ($request->header('x-device-name') ?? ''));
        if ($name === '') {
            return 'Unknown device';
        }
        return mb_substr(preg_replace('/[^\p{L}\p{N} \-_.()]/u', '', $name) ?? 'Unknown device', 0, 120);
    }

    private static function platform(Request $request): string
    {
        $platform = strtolower(trim((string) ($request->header('x-platform') ?? '')));
        return in_array($platform, ['ios', 'ipados', 'macos', 'android', 'web'], true) ? $platform : 'unknown';
    }
}
