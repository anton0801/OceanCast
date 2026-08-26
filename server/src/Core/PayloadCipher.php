<?php

declare(strict_types=1);

namespace OceanCast\Core;

/**
 * AES-256-GCM for the app -> API layer. The client (CryptoKit) sends the sealed
 * box as base64 of nonce(12) || ciphertext || tag(16); the same layout is used
 * here so the two sides interoperate without agreeing on anything but the key.
 */
final class PayloadCipher
{
    private const NONCE_BYTES = 12;
    private const TAG_BYTES = 16;

    public static function isConfigured(): bool
    {
        return self::key() !== null;
    }

    /** Decrypts a base64 sealed box, or null when it cannot be authenticated. */
    public static function open(string $base64): ?string
    {
        $key = self::key();
        if ($key === null) {
            return null;
        }
        $raw = base64_decode(trim($base64), true);
        if ($raw === false || strlen($raw) < self::NONCE_BYTES + self::TAG_BYTES + 1) {
            return null;
        }

        $nonce = substr($raw, 0, self::NONCE_BYTES);
        $tag = substr($raw, -self::TAG_BYTES);
        $cipher = substr($raw, self::NONCE_BYTES, -self::TAG_BYTES);

        $plain = openssl_decrypt($cipher, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $nonce, $tag);
        return $plain === false ? null : $plain;
    }

    /** Seals a string into the same base64 layout (used by tests and tooling). */
    public static function seal(string $plain): ?string
    {
        $key = self::key();
        if ($key === null) {
            return null;
        }
        $nonce = random_bytes(self::NONCE_BYTES);
        $tag = '';
        $cipher = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $nonce, $tag, '', self::TAG_BYTES);
        if ($cipher === false) {
            return null;
        }
        return base64_encode($nonce . $cipher . $tag);
    }

    private static function key(): ?string
    {
        $hex = Config::string('ATTR_PAYLOAD_KEY', '');
        if ($hex === '' || strlen($hex) !== 64 || !ctype_xdigit($hex)) {
            return null;
        }
        $key = hex2bin($hex);
        return $key === false ? null : $key;
    }
}
