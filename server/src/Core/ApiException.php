<?php

declare(strict_types=1);

namespace OceanCast\Core;

/**
 * Every failure the client is allowed to see. The message is safe to display;
 * anything sensitive stays in the server log.
 */
final class ApiException extends \RuntimeException
{
    /** @param array<string,string> $fields */
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly array $fields = [],
        public readonly ?string $logDetail = null,
    ) {
        parent::__construct($message);
    }

    /** @param array<string,string> $fields */
    public static function validation(string $message, array $fields = []): self
    {
        return new self(422, 'validation_failed', $message, $fields);
    }

    public static function unauthorized(string $message = 'Authentication is required.', string $code = 'unauthorized'): self
    {
        return new self(401, $code, $message);
    }

    public static function forbidden(string $message = 'You do not have access to this resource.'): self
    {
        return new self(403, 'forbidden', $message);
    }

    public static function notFound(string $message = 'Resource not found.'): self
    {
        return new self(404, 'not_found', $message);
    }

    public static function conflict(string $message, string $code = 'conflict'): self
    {
        return new self(409, $code, $message);
    }

    public static function tooManyRequests(string $message, int $retryAfter): self
    {
        $exception = new self(429, 'rate_limited', $message);
        header('Retry-After: ' . max(1, $retryAfter));
        return $exception;
    }

    public static function payloadTooLarge(string $message = 'The request body is too large.'): self
    {
        return new self(413, 'payload_too_large', $message);
    }

    public static function badRequest(string $message, string $code = 'bad_request'): self
    {
        return new self(400, $code, $message);
    }
}
