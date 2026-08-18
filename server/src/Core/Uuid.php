<?php

declare(strict_types=1);

namespace OceanCast\Core;

final class Uuid
{
    public static function v4(): string
    {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        return strtoupper(vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4)));
    }

    public static function isValid(string $value): bool
    {
        return (bool) preg_match(
            '/^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/',
            $value
        );
    }

    /** The app produces uppercase UUIDs; normalise so lookups always match. */
    public static function normalize(string $value): string
    {
        return strtoupper(trim($value));
    }
}
