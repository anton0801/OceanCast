<?php

declare(strict_types=1);

namespace OceanCast\Core;

final class Response
{
    /** @param array<string,mixed>|list<mixed> $payload */
    public function __construct(
        public readonly int $status = 200,
        public readonly array $payload = [],
        /** @var array<string,string> */
        public readonly array $headers = [],
    ) {
    }

    /** @param array<string,mixed>|list<mixed> $payload */
    public static function ok(array $payload = [], array $headers = []): self
    {
        return new self(200, $payload, $headers);
    }

    /** @param array<string,mixed> $payload */
    public static function created(array $payload, array $headers = []): self
    {
        return new self(201, $payload, $headers);
    }

    public static function noContent(): self
    {
        return new self(204, []);
    }

    public function send(): void
    {
        if (!headers_sent()) {
            http_response_code($this->status);
            header('Content-Type: application/json; charset=utf-8');
            foreach ($this->headers as $name => $value) {
                header($name . ': ' . $value);
            }
        }

        if ($this->status === 204) {
            return;
        }

        echo json_encode(
            $this->payload,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PRESERVE_ZERO_FRACTION
        );
    }

    /** Security headers applied to every response, including errors. */
    public static function applySecurityHeaders(): void
    {
        if (headers_sent()) {
            return;
        }
        header_remove('X-Powered-By');
        header('X-Content-Type-Options: nosniff');
        header('X-Frame-Options: DENY');
        header('Referrer-Policy: no-referrer');
        header('Permissions-Policy: geolocation=(), microphone=(), camera=(), interest-cohort=()');
        header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'");
        header('Cache-Control: no-store, no-cache, must-revalidate, private');
        header('Pragma: no-cache');
        header('Cross-Origin-Resource-Policy: same-origin');

        if (Config::bool('FORCE_HTTPS', true)) {
            header('Strict-Transport-Security: max-age=31536000; includeSubDomains');
        }
    }

    /**
     * CORS is closed by default. A native app does not need it; browsers only get
     * through when the origin is on the explicit allow-list.
     */
    public static function applyCors(Request $request): void
    {
        $allowed = Config::list('CORS_ALLOWED_ORIGINS', []);
        $origin = $request->header('origin');
        if ($origin === null || $allowed === [] || !in_array($origin, $allowed, true)) {
            return;
        }
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Vary: Origin');
        header('Access-Control-Allow-Headers: Authorization, Content-Type, Idempotency-Key, X-Device-Name, X-Platform');
        header('Access-Control-Allow-Methods: GET, POST, PATCH, PUT, DELETE, OPTIONS');
        header('Access-Control-Max-Age: 600');
    }
}
