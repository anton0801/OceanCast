<?php

declare(strict_types=1);

namespace OceanCast\Core;

/**
 * Minimal outbound JSON POST used to forward attribution to the external
 * analytics service. curl when it is available, a stream context otherwise.
 * No User-Agent is sent — this deployment does not use one.
 */
final class OutboundHttp
{
    /**
     * @param array<string,mixed> $body
     * @return array{code:int,body:string}
     */
    public static function postJson(string $url, array $body, int $timeoutSeconds = 8): array
    {
        $json = json_encode($body, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false) {
            return ['code' => 0, 'body' => ''];
        }

        if (function_exists('curl_init')) {
            return self::viaCurl($url, $json, $timeoutSeconds);
        }
        return self::viaStream($url, $json, $timeoutSeconds);
    }

    /** @return array{code:int,body:string} */
    private static function viaCurl(string $url, string $json, int $timeout): array
    {
        $handle = curl_init($url);
        if ($handle === false) {
            return ['code' => 0, 'body' => ''];
        }
        curl_setopt_array($handle, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $json,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
            CURLOPT_CONNECTTIMEOUT => $timeout,
            CURLOPT_USERAGENT      => '',
            CURLOPT_HTTPHEADER     => [
                'Content-Type: application/json',
                'Accept: application/json',
                'Content-Length: ' . strlen($json),
            ],
        ]);
        $response = curl_exec($handle);
        $code = (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        // The handle is a resource-object; it frees itself when it goes out of
        // scope. curl_close() is a no-op since PHP 8.0 and removed later.

        return ['code' => $code, 'body' => is_string($response) ? $response : ''];
    }

    /** @return array{code:int,body:string} */
    private static function viaStream(string $url, string $json, int $timeout): array
    {
        $context = stream_context_create([
            'http' => [
                'method'        => 'POST',
                'header'        => "Content-Type: application/json\r\nAccept: application/json\r\n",
                'content'       => $json,
                'timeout'       => $timeout,
                'ignore_errors' => true,
                'user_agent'    => '',
            ],
        ]);

        $body = @file_get_contents($url, false, $context);
        $code = 0;
        foreach ($http_response_header ?? [] as $line) {
            if (preg_match('#^HTTP/\S+\s+(\d{3})#', $line, $m) === 1) {
                $code = (int) $m[1];
            }
        }
        return ['code' => $code, 'body' => is_string($body) ? $body : ''];
    }
}
