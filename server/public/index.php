<?php

declare(strict_types=1);

/**
 * Ocean Cast API — single front controller.
 *
 * Everything below /v1 requires a bearer access token except the four public
 * auth endpoints and the health probe.
 */

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Core\Router;
use OceanCast\Http\Auth;
use OceanCast\Http\Controllers\AuthController;
use OceanCast\Http\Controllers\HouseholdController;
use OceanCast\Http\Controllers\ProfileController;
use OceanCast\Http\Controllers\ResourceController;
use OceanCast\Http\Controllers\SyncController;
use OceanCast\Security\RateLimiter;
use OceanCast\Security\TokenService;

require dirname(__DIR__) . '/src/bootstrap.php';

Response::applySecurityHeaders();

$request = Request::capture();
Response::applyCors($request);

if ($request->method === 'OPTIONS') {
    (new Response(204))->send();
    exit;
}

// Refuse to move credentials over plain HTTP in production.
if (Config::bool('FORCE_HTTPS', true) && !$request->isSecure()) {
    (new Response(403, [
        'error' => [
            'code'    => 'https_required',
            'message' => 'This API is only available over HTTPS.',
        ],
    ]))->send();
    exit;
}

$router = new Router();

$auth      = new AuthController();
$profile   = new ProfileController();
$household = new HouseholdController();
$resources = new ResourceController();
$sync      = new SyncController();

// ------------------------------------------------------------------- public

$router->get('/v1/health', static fn (Request $r): Response => Response::ok([
    'status'  => 'ok',
    'time'    => gmdate('c'),
    'version' => 'v1',
]), auth: false);

$router->post('/v1/auth/register', static fn (Request $r): Response => $auth->register($r), auth: false);
$router->post('/v1/auth/login', static fn (Request $r): Response => $auth->login($r), auth: false);
$router->post('/v1/auth/refresh', static fn (Request $r): Response => $auth->refresh($r), auth: false);

// ---------------------------------------------------------------- protected

$router->post('/v1/auth/logout', static fn (Request $r, Auth $a): Response => $auth->logout($r, $a));
$router->post('/v1/auth/logout-all', static fn (Request $r, Auth $a): Response => $auth->logoutAll($r, $a));
$router->get('/v1/auth/sessions', static fn (Request $r, Auth $a): Response => $auth->sessions($r, $a));
$router->delete('/v1/auth/sessions/{id}', static fn (Request $r, Auth $a, array $p): Response => $auth->revokeSession($r, $a, $p));

$router->get('/v1/profile', static fn (Request $r, Auth $a): Response => $profile->show($r, $a));
$router->patch('/v1/profile', static fn (Request $r, Auth $a): Response => $profile->update($r, $a));
$router->post('/v1/profile/password', static fn (Request $r, Auth $a): Response => $profile->changePassword($r, $a));
$router->get('/v1/profile/export', static fn (Request $r, Auth $a): Response => $profile->export($r, $a));
$router->delete('/v1/profile', static fn (Request $r, Auth $a): Response => $profile->destroy($r, $a));

$router->get('/v1/household', static fn (Request $r, Auth $a): Response => $household->show($r, $a));
$router->put('/v1/household', static fn (Request $r, Auth $a): Response => $household->replace($r, $a));
$router->delete('/v1/household', static fn (Request $r, Auth $a): Response => $household->destroy($r, $a));

$router->get('/v1/settings', static fn (Request $r, Auth $a): Response => $household->showSettings($r, $a));
$router->put('/v1/settings', static fn (Request $r, Auth $a): Response => $household->replaceSettings($r, $a));

$router->post('/v1/sync', static fn (Request $r, Auth $a): Response => $sync->sync($r, $a));

$router->get('/v1/{resource}', static fn (Request $r, Auth $a, array $p): Response => $resources->index($r, $a, $p));
$router->post('/v1/{resource}', static fn (Request $r, Auth $a, array $p): Response => $resources->store($r, $a, $p));
$router->get('/v1/{resource}/{id}', static fn (Request $r, Auth $a, array $p): Response => $resources->show($r, $a, $p));
$router->put('/v1/{resource}/{id}', static fn (Request $r, Auth $a, array $p): Response => $resources->replace($r, $a, $p));
$router->patch('/v1/{resource}/{id}', static fn (Request $r, Auth $a, array $p): Response => $resources->patch($r, $a, $p));
$router->delete('/v1/{resource}/{id}', static fn (Request $r, Auth $a, array $p): Response => $resources->destroy($r, $a, $p));

// ------------------------------------------------------------------ dispatch

$route = $router->match($request->method, $request->path);

$context = null;
if ($route['auth']) {
    $token = $request->bearerToken();
    if ($token === null) {
        throw ApiException::unauthorized('Send an access token in the Authorization header.', 'missing_token');
    }

    $identity = TokenService::authenticate($token);
    $context = new Auth($identity['user'], $identity['token']);

    // Per-session ceiling: a stolen token still cannot hammer the API.
    RateLimiter::hit(
        'api:token',
        (string) $context->tokenId(),
        Config::int('RATE_REQUESTS_PER_MINUTE', 240),
        60
    );
} else {
    RateLimiter::hit('api:ip', $request->ip, Config::int('RATE_PUBLIC_PER_MINUTE', 60), 60);
}

// Idempotent POSTs: a retried request returns the first response instead of
// creating a second record.
$idempotencyKey = $request->header('idempotency-key');
$idempotent = $context !== null
    && $request->method === 'POST'
    && $idempotencyKey !== null
    && preg_match('/^[A-Za-z0-9\-_]{8,64}$/', $idempotencyKey) === 1;

if ($idempotent) {
    $hashed = hash('sha256', $idempotencyKey);
    $cached = Database::first(
        'SELECT response_code, response_body FROM idempotency_keys
          WHERE user_id = :user AND idem_key = :key AND method_path = :path LIMIT 1',
        ['user' => $context->userId(), 'key' => $hashed, 'path' => $request->method . ' ' . $request->path]
    );
    if ($cached !== null) {
        http_response_code((int) $cached['response_code']);
        header('Content-Type: application/json; charset=utf-8');
        header('Idempotent-Replay: true');
        echo (string) $cached['response_body'];
        exit;
    }
}

/** @var Response $response */
$response = $route['auth']
    ? ($route['handler'])($request, $context, $route['params'])
    : ($route['handler'])($request, $route['params']);

if ($idempotent && $response->status < 500) {
    Database::run(
        'INSERT INTO idempotency_keys (user_id, idem_key, method_path, response_code, response_body, created_at)
         VALUES (:user, :key, :path, :code, :body, :now)
         ON DUPLICATE KEY UPDATE response_code = VALUES(response_code)',
        [
            'user' => $context->userId(),
            'key'  => hash('sha256', (string) $idempotencyKey),
            'path' => $request->method . ' ' . $request->path,
            'code' => $response->status,
            'body' => json_encode($response->payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            'now'  => gmdate('Y-m-d H:i:s.u'),
        ]
    );
}

$response->send();
