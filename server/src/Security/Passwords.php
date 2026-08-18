<?php

declare(strict_types=1);

namespace OceanCast\Security;

use OceanCast\Core\Config;

/**
 * Argon2id hashing. Cost parameters live in configuration so they can be raised
 * as hardware improves; existing hashes are re-hashed transparently on login.
 */
final class Passwords
{
    public static function hash(string $plain): string
    {
        $hash = password_hash($plain, PASSWORD_ARGON2ID, self::options());
        if (!is_string($hash) || $hash === '') {
            throw new \RuntimeException('Password hashing failed.');
        }
        return $hash;
    }

    public static function verify(string $plain, string $hash): bool
    {
        return password_verify($plain, $hash);
    }

    public static function needsRehash(string $hash): bool
    {
        return password_needs_rehash($hash, PASSWORD_ARGON2ID, self::options());
    }

    /**
     * Burns the same amount of time as a real verification so a missing account
     * cannot be told apart from a wrong password by timing alone.
     */
    public static function burnTime(): void
    {
        password_verify(
            'timing-equaliser',
            '$argon2id$v=19$m=65536,t=4,p=2$YWJjZGVmZ2hpamtsbW5vcA$0dQBv3W2hVzKrbYbGvVL0bF2VtqvJc8x0m1Yd1EF7Nw'
        );
    }

    /** @return array<string,int> */
    private static function options(): array
    {
        return [
            'memory_cost' => Config::int('ARGON_MEMORY_KIB', 65536),
            'time_cost'   => Config::int('ARGON_TIME_COST', 4),
            'threads'     => Config::int('ARGON_THREADS', 2),
        ];
    }
}
