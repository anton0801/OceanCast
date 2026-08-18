<?php

declare(strict_types=1);

namespace OceanCast\Core;

/**
 * Immutable view of the incoming request. The JSON body is parsed once, with a
 * hard size and depth limit so a malicious payload cannot exhaust memory.
 */
final class Request
{
    private const MAX_BODY_BYTES = 4_194_304; // 4 MB
    private const MAX_JSON_DEPTH = 32;

    /** @var array<string,mixed> */
    private array $json = [];
    private bool $jsonParsed = false;

    private function __construct(
        public readonly string $method,
        public readonly string $path,
        /** @var array<string,string> */
        public readonly array $query,
        /** @var array<string,string> */
        public readonly array $headers,
        public readonly string $rawBody,
        public readonly string $ip,
    ) {
    }

    public static function capture(): self
    {
        $method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');
        $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
        $path = parse_url($uri, PHP_URL_PATH) ?: '/';
        $path = '/' . trim((string) $path, '/');

        // Strip a sub-directory prefix when the API is not mounted at the domain root.
        $base = trim(Config::string('APP_BASE_PATH', ''), '/');
        if ($base !== '' && str_starts_with($path, '/' . $base)) {
            $path = '/' . ltrim(substr($path, strlen($base) + 1), '/');
        }

        $headers = [];
        foreach ($_SERVER as $key => $value) {
            $name = (string) $key;

            // An internal rewrite prefixes every header with REDIRECT_, and a
            // second rewrite prefixes it again. On CGI/FastCGI hosting (LiteSpeed
            // on Hostinger, Apache + php-cgi, most cPanel setups) the bearer token
            // therefore arrives as REDIRECT_HTTP_AUTHORIZATION and never as
            // HTTP_AUTHORIZATION — without unwrapping this, every authenticated
            // request answers 401.
            $direct = str_starts_with($name, 'HTTP_');
            while (str_starts_with($name, 'REDIRECT_')) {
                $name = substr($name, 9);
            }
            if (!str_starts_with($name, 'HTTP_')) {
                continue;
            }

            $header = strtolower(str_replace('_', '-', substr($name, 5)));
            // A header sent straight to PHP wins over a rewritten copy of itself.
            if ($direct || !isset($headers[$header])) {
                $headers[$header] = (string) $value;
            }
        }

        // Last resort for servers that expose the header only through the SAPI.
        if (!isset($headers['authorization']) && function_exists('apache_request_headers')) {
            foreach ((array) apache_request_headers() as $key => $value) {
                if (strcasecmp((string) $key, 'Authorization') === 0 && is_string($value)) {
                    $headers['authorization'] = $value;
                    break;
                }
            }
        }
        if (isset($_SERVER['CONTENT_TYPE'])) {
            $headers['content-type'] = (string) $_SERVER['CONTENT_TYPE'];
        }
        if (isset($_SERVER['CONTENT_LENGTH'])) {
            $headers['content-length'] = (string) $_SERVER['CONTENT_LENGTH'];
        }

        $declared = (int) ($headers['content-length'] ?? 0);
        if ($declared > self::MAX_BODY_BYTES) {
            throw ApiException::payloadTooLarge();
        }

        $body = $method === 'GET' || $method === 'HEAD'
            ? ''
            : (string) file_get_contents('php://input', false, null, 0, self::MAX_BODY_BYTES + 1);

        if (strlen($body) > self::MAX_BODY_BYTES) {
            throw ApiException::payloadTooLarge();
        }

        $query = [];
        foreach ($_GET as $key => $value) {
            if (is_string($key) && is_scalar($value)) {
                $query[$key] = (string) $value;
            }
        }

        return new self($method, $path, $query, $headers, $body, self::clientIp($headers));
    }

    public function header(string $name): ?string
    {
        return $this->headers[strtolower($name)] ?? null;
    }

    public function bearerToken(): ?string
    {
        $header = $this->header('authorization');
        if ($header === null) {
            return null;
        }
        if (!preg_match('/^Bearer\s+([A-Za-z0-9\-\._~\+\/=]+)$/', trim($header), $matches)) {
            return null;
        }
        return $matches[1];
    }

    /** @return array<string,mixed> */
    public function json(): array
    {
        if ($this->jsonParsed) {
            return $this->json;
        }
        $this->jsonParsed = true;

        if ($this->rawBody === '') {
            return $this->json = [];
        }

        $contentType = strtolower((string) ($this->header('content-type') ?? ''));
        if ($contentType !== '' && !str_contains($contentType, 'application/json')) {
            throw ApiException::badRequest('Send the body as application/json.', 'unsupported_media_type');
        }

        try {
            $decoded = json_decode($this->rawBody, true, self::MAX_JSON_DEPTH, JSON_THROW_ON_ERROR);
        } catch (\JsonException $error) {
            throw ApiException::badRequest('The request body is not valid JSON.', 'invalid_json');
        }

        if (!is_array($decoded)) {
            throw ApiException::badRequest('The request body must be a JSON object.', 'invalid_json');
        }

        return $this->json = $decoded;
    }

    public function queryString(string $key, ?string $default = null): ?string
    {
        $value = $this->query[$key] ?? null;
        return $value === null || $value === '' ? $default : $value;
    }

    public function queryInt(string $key, int $default): int
    {
        $value = $this->query[$key] ?? null;
        return $value === null || !is_numeric($value) ? $default : (int) $value;
    }

    public function isSecure(): bool
    {
        if (($_SERVER['HTTPS'] ?? '') !== '' && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
            return true;
        }
        if ((int) ($_SERVER['SERVER_PORT'] ?? 0) === 443) {
            return true;
        }

        // A forwarded header is only believed when the request really came from
        // a proxy we listed, or when the deployment states it sits behind a
        // TLS-terminating one. Trusting it blindly would let anybody claim HTTPS.
        $trusted = Config::list('TRUSTED_PROXIES', []);
        $remote = (string) ($_SERVER['REMOTE_ADDR'] ?? '');
        $behindProxy = Config::bool('TRUST_FORWARDED_PROTO', false)
            || ($trusted !== [] && in_array($remote, $trusted, true));

        if ($behindProxy) {
            if (strtolower((string) ($this->header('x-forwarded-proto') ?? '')) === 'https') {
                return true;
            }
            if (strtolower((string) ($this->header('x-forwarded-ssl') ?? '')) === 'on') {
                return true;
            }
        }
        return false;
    }

    /** @param array<string,string> $headers */
    private static function clientIp(array $headers): string
    {
        $remote = (string) ($_SERVER['REMOTE_ADDR'] ?? '0.0.0.0');

        // Only trust forwarding headers from proxies we explicitly listed.
        $trusted = Config::list('TRUSTED_PROXIES', []);
        if ($trusted !== [] && in_array($remote, $trusted, true)) {
            $forwarded = $headers['x-forwarded-for'] ?? '';
            if ($forwarded !== '') {
                $first = trim(explode(',', $forwarded)[0]);
                if (filter_var($first, FILTER_VALIDATE_IP) !== false) {
                    return $first;
                }
            }
        }
        return $remote;
    }
}
