<?php

declare(strict_types=1);

/**
 * Bootstrap: autoloading, error handling and hardening that must be in place
 * before a single line of application code runs.
 */

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Response;

// ---------------------------------------------------------------- autoloader

spl_autoload_register(static function (string $class): void {
    $prefix = 'OceanCast\\';
    if (!str_starts_with($class, $prefix)) {
        return;
    }
    $relative = substr($class, strlen($prefix));
    $path = __DIR__ . '/' . str_replace('\\', '/', $relative) . '.php';
    if (is_file($path)) {
        require_once $path;
    }
});

// ------------------------------------------------------------- configuration

Config::load(dirname(__DIR__) . '/.env');

// Never leak internals to a client in production; log them instead.
$isProduction = Config::isProduction();
ini_set('display_errors', $isProduction ? '0' : '1');
ini_set('log_errors', '1');
ini_set('zend.exception_ignore_args', '1');
error_reporting(E_ALL);
date_default_timezone_set('UTC');

$logFile = Config::string('LOG_FILE', dirname(__DIR__) . '/storage/api.log');
if (!is_dir(dirname($logFile))) {
    @mkdir(dirname($logFile), 0770, true);
}
ini_set('error_log', $logFile);

// A missing APP_KEY would silently weaken every HMAC in the system.
$appKey = Config::string('APP_KEY', '');
if (strlen($appKey) < 32) {
    http_response_code(500);
    header('Content-Type: application/json');
    echo json_encode([
        'error' => [
            'code'    => 'server_misconfigured',
            'message' => 'The server is not configured. Set APP_KEY (32+ characters) in .env.',
        ],
    ]);
    exit;
}

// ------------------------------------------------------------ error handlers

set_error_handler(static function (int $severity, string $message, string $file, int $line): bool {
    if ((error_reporting() & $severity) === 0) {
        return false;
    }
    throw new ErrorException($message, 0, $severity, $file, $line);
});

set_exception_handler(static function (Throwable $error): void {
    Response::applySecurityHeaders();

    if ($error instanceof ApiException) {
        $payload = [
            'error' => [
                'code'    => $error->errorCode,
                'message' => $error->getMessage(),
            ],
        ];
        if ($error->fields !== []) {
            $payload['error']['fields'] = $error->fields;
        }
        (new Response($error->status, $payload))->send();
        return;
    }

    error_log(sprintf(
        '[%s] %s in %s:%d%s%s',
        date('c'),
        $error->getMessage(),
        $error->getFile(),
        $error->getLine(),
        PHP_EOL,
        $error->getTraceAsString()
    ));

    $message = Config::isProduction()
        ? 'Something went wrong on our side. Nothing was changed.'
        : $error->getMessage();

    (new Response(500, ['error' => ['code' => 'server_error', 'message' => $message]]))->send();
});
