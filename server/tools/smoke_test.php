<?php

declare(strict_types=1);

/**
 * End-to-end check of the API, including the security behaviour.
 *
 *   php tools/smoke_test.php http://127.0.0.1:8787
 *
 * It creates two throwaway accounts and deletes them again, so it is safe to
 * run against a staging database. Do not point it at production data.
 */

$base = rtrim($argv[1] ?? 'http://127.0.0.1:8787', '/');
$passed = 0;
$failed = 0;

function call(string $method, string $path, ?array $body = null, ?string $token = null, array $headers = []): array
{
    global $base;
    $ch = curl_init($base . $path);
    $requestHeaders = ['Accept: application/json'];
    if ($body !== null) {
        $requestHeaders[] = 'Content-Type: application/json';
    }
    if ($token !== null) {
        $requestHeaders[] = 'Authorization: Bearer ' . $token;
    }
    foreach ($headers as $name => $value) {
        $requestHeaders[] = $name . ': ' . $value;
    }

    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPHEADER     => $requestHeaders,
        CURLOPT_TIMEOUT        => 20,
    ]);
    if ($body !== null) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body, JSON_UNESCAPED_UNICODE));
    }

    $raw = curl_exec($ch);
    if ($raw === false) {
        fwrite(STDERR, "Request failed: " . curl_error($ch) . "\n");
        exit(1);
    }
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);

    return ['status' => $status, 'body' => json_decode((string) $raw, true) ?? []];
}

function check(string $label, bool $condition, string $detail = ''): void
{
    global $passed, $failed;
    if ($condition) {
        $passed++;
        fwrite(STDOUT, "  ok    {$label}\n");
    } else {
        $failed++;
        fwrite(STDOUT, "  FAIL  {$label}" . ($detail !== '' ? "  ({$detail})" : '') . "\n");
    }
}

function uuid(): string
{
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    return strtoupper(vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4)));
}

$suffix = bin2hex(random_bytes(6));
$emailA = "smoke-a-{$suffix}@example.test";
$emailB = "smoke-b-{$suffix}@example.test";
$password = 'Str0ngPassphrase!' . $suffix;

fwrite(STDOUT, "Ocean Cast API smoke test → {$base}\n\n");

// ------------------------------------------------------------------ health
fwrite(STDOUT, "Health\n");
$r = call('GET', '/v1/health');
check('health returns 200', $r['status'] === 200, 'got ' . $r['status']);

// -------------------------------------------------------------------- auth
fwrite(STDOUT, "\nRegistration and login\n");
$r = call('POST', '/v1/auth/register', [
    'email' => $emailA, 'password' => $password, 'displayName' => 'Smoke A',
], null, ['X-Device-Name' => 'Smoke iPhone', 'X-Platform' => 'ios']);
check('register returns 201', $r['status'] === 201, 'got ' . $r['status']);
$tokenA = $r['body']['auth']['accessToken'] ?? '';
$refreshA = $r['body']['auth']['refreshToken'] ?? '';
check('access token issued', str_starts_with($tokenA, 'sb_at_'));
check('refresh token issued', str_starts_with($refreshA, 'sb_rt_'));

$r = call('POST', '/v1/auth/register', ['email' => $emailA, 'password' => $password, 'displayName' => 'Dup']);
check('duplicate email rejected', $r['status'] === 409, 'got ' . $r['status']);

$r = call('POST', '/v1/auth/register', ['email' => 'nope', 'password' => 'short', 'displayName' => '']);
check('weak input rejected with field errors', $r['status'] === 422 && isset($r['body']['error']['fields']['password']));

$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => 'WrongPassword123']);
check('wrong password rejected', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'invalid_credentials');

$r = call('POST', '/v1/auth/login', ['email' => "unknown-{$suffix}@example.test", 'password' => $password]);
check('unknown account gives the same error', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'invalid_credentials');

$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => $password],
    null, ['X-Device-Name' => 'Smoke iPad', 'X-Platform' => 'ipados']);
check('login returns 200', $r['status'] === 200, 'got ' . $r['status']);
$tokenA2 = $r['body']['auth']['accessToken'] ?? '';

// ------------------------------------------------------------------- token
fwrite(STDOUT, "\nToken enforcement\n");
$r = call('GET', '/v1/profile');
check('no token → 401 missing_token', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'missing_token');

$r = call('GET', '/v1/profile', null, 'sb_at_' . str_repeat('0', 64));
check('forged token → 401 invalid_token', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'invalid_token');

$r = call('GET', '/v1/profile', null, 'not-even-a-token');
check('malformed token → 401', $r['status'] === 401);

$r = call('GET', '/v1/profile', null, $tokenA);
check('valid token → 200', $r['status'] === 200 && ($r['body']['user']['email'] ?? '') === $emailA);

// --------------------------------------------------------------- household
fwrite(STDOUT, "\nHousehold and resources\n");
$householdId = uuid();
$r = call('PUT', '/v1/household', [
    'id' => $householdId, 'name' => 'Smoke Kitchen', 'currencyCode' => 'USD',
    'preferences' => ['defaultStore' => 'Corner Market', 'groupByStore' => true, 'expiryWindowDays' => 3],
], $tokenA);
check('household created', $r['status'] === 200 && ($r['body']['household']['id'] ?? '') === $householdId, 'got ' . $r['status']);

$zoneId = uuid();
$r = call('POST', '/v1/zones', ['id' => $zoneId, 'name' => 'Fridge', 'kind' => 'fridge'], $tokenA);
check('zone created', $r['status'] === 201, 'got ' . $r['status']);

$r = call('POST', '/v1/zones', ['id' => $zoneId, 'name' => 'Fridge again', 'kind' => 'fridge'], $tokenA);
check('duplicate id rejected', $r['status'] === 409);

$r = call('POST', '/v1/zones', ['id' => uuid(), 'name' => 'Bad', 'kind' => 'spaceship'], $tokenA);
check('invalid enum rejected', $r['status'] === 422 && isset($r['body']['error']['fields']['kind']));

$batchId = uuid();
$r = call('POST', '/v1/batches', [
    'id' => $batchId, 'productName' => 'Greek Yoghurt', 'brand' => 'Meadow',
    'quantity' => 4, 'remaining' => 3, 'unit' => 'piece',
    'bestBefore' => gmdate('Y-m-d', time() + 86400), 'zoneID' => $zoneId,
    'price' => 5.6, 'store' => 'Corner Market', 'origin' => 'manual',
], $tokenA);
check('batch created', $r['status'] === 201, json_encode($r['body']));
check('numbers come back as numbers', ($r['body']['item']['remaining'] ?? null) === 3.0);
check('server stamps updatedAt', !empty($r['body']['item']['updatedAt']));

$r = call('POST', '/v1/batches', ['id' => uuid(), 'productName' => 'Bad', 'quantity' => -5, 'remaining' => 1, 'unit' => 'piece'], $tokenA);
check('negative quantity rejected', $r['status'] === 422 && isset($r['body']['error']['fields']['quantity']));

$r = call('PATCH', '/v1/batches/' . $batchId, ['remaining' => 2, 'opened' => true], $tokenA);
check('patch applies', $r['status'] === 200 && ($r['body']['item']['remaining'] ?? null) === 2.0);
check('patch keeps other fields', ($r['body']['item']['productName'] ?? '') === 'Greek Yoghurt');

$r = call('GET', '/v1/batches?limit=10', null, $tokenA);
check('list returns the batch', $r['status'] === 200 && count($r['body']['items'] ?? []) === 1);

$r = call('GET', '/v1/batches/' . $batchId, null, $tokenA);
check('read one works', $r['status'] === 200);

// --------------------------------------------------------------- injection
fwrite(STDOUT, "\nInjection and traversal attempts\n");
$r = call('GET', "/v1/batches/" . rawurlencode("' OR 1=1 -- "), null, $tokenA);
check("SQL in path is rejected, not executed", in_array($r['status'], [404, 422], true), 'got ' . $r['status']);

$r = call('GET', '/v1/batches?since=' . rawurlencode("2020-01-01' OR '1'='1"), null, $tokenA);
check('SQL in query is rejected', in_array($r['status'], [200, 422], true) && !isset($r['body']['error']['sql']));

$r = call('POST', '/v1/batches', [
    'id' => uuid(), 'productName' => "Robert'); DROP TABLE batches;--",
    'quantity' => 1, 'remaining' => 1, 'unit' => 'piece',
], $tokenA);
check('quoted name is stored, not executed', $r['status'] === 201);
$r = call('GET', '/v1/batches?limit=10', null, $tokenA);
check('table still exists after injection attempt', $r['status'] === 200 && count($r['body']['items'] ?? []) === 2);

$r = call('POST', '/v1/zones', ['id' => uuid(), 'name' => 'X', 'kind' => 'other', 'household_id' => 999999], $tokenA);
check('unknown fields are ignored (no mass assignment)', $r['status'] === 201);

$r = call('GET', '/v1/../../etc/passwd', null, $tokenA);
check('path traversal → 404', $r['status'] === 404);

// ------------------------------------------------------------- isolation
fwrite(STDOUT, "\nAccount isolation\n");
$r = call('POST', '/v1/auth/register', ['email' => $emailB, 'password' => $password, 'displayName' => 'Smoke B']);
check('second account created', $r['status'] === 201);
$tokenB = $r['body']['auth']['accessToken'] ?? '';

$r = call('GET', '/v1/batches/' . $batchId, null, $tokenB);
check("other account cannot read A's batch", in_array($r['status'], [404, 409], true), 'got ' . $r['status']);

$r = call('PATCH', '/v1/batches/' . $batchId, ['remaining' => 99], $tokenB);
check("other account cannot write A's batch", in_array($r['status'], [404, 409], true));

$r = call('PUT', '/v1/household', ['id' => $householdId, 'name' => 'Hijack', 'currencyCode' => 'USD'], $tokenB);
check("other account cannot claim A's household", $r['status'] === 403, 'got ' . $r['status']);

$r = call('GET', '/v1/batches/' . $batchId, null, $tokenA);
check("A's data is untouched", $r['status'] === 200 && ($r['body']['item']['remaining'] ?? null) === 2.0);

// ------------------------------------------------------------ idempotency
fwrite(STDOUT, "\nIdempotency and sync\n");
$key = 'smoke-' . bin2hex(random_bytes(8));
$idemBody = ['id' => uuid(), 'name' => 'Basil', 'quantity' => 1, 'unit' => 'pack'];
$r1 = call('POST', '/v1/shopping-items', $idemBody, $tokenA, ['Idempotency-Key' => $key]);
$r2 = call('POST', '/v1/shopping-items', $idemBody, $tokenA, ['Idempotency-Key' => $key]);
check('repeated POST with same key does not duplicate', $r1['status'] === 201 && $r2['status'] === 201);
$r = call('GET', '/v1/shopping-items', null, $tokenA);
check('only one shopping item exists', count($r['body']['items'] ?? []) === 1, 'got ' . count($r['body']['items'] ?? []));

$mealId = uuid();
$ingredientId = uuid();
$r = call('POST', '/v1/sync', [
    'since'   => null,
    'changes' => [
        'meals' => [[
            'id' => $mealId, 'name' => 'Tomato Pasta', 'servings' => 2,
            'date' => gmdate('Y-m-d', time() + 86400), 'status' => 'planned',
            'ingredients' => [['id' => $ingredientId, 'name' => 'Spaghetti', 'quantityPerServing' => 0.12, 'unit' => 'kilogram']],
        ]],
        'reservations' => [[
            'id' => uuid(), 'mealID' => $mealId, 'ingredientID' => $ingredientId,
            'batchID' => $batchId, 'quantity' => 0.24,
        ]],
    ],
    'settings' => ['expiryWindowDays' => 3, 'notificationsEnabled' => false],
], $tokenA);
check('sync push accepted', $r['status'] === 200 && ($r['body']['applied']['meals'] ?? 0) === 1, json_encode($r['body']['rejected'] ?? []));
check('sync pull returns batches', count($r['body']['changes']['batches'] ?? []) === 2);
check('sync returns server cursor', !empty($r['body']['serverTime']));
$cursor = $r['body']['serverTime'] ?? '';

$r = call('POST', '/v1/sync', ['since' => $cursor, 'changes' => []], $tokenA);
check('delta pull after cursor is empty', ($r['body']['changes']['batches'] ?? []) === []);

$r = call('DELETE', '/v1/batches/' . $batchId, null, $tokenA);
check('soft delete works', $r['status'] === 200);
$r = call('GET', '/v1/batches/' . $batchId, null, $tokenA);
check('deleted record is gone from reads', $r['status'] === 404);
$r = call('POST', '/v1/sync', ['since' => $cursor, 'changes' => []], $tokenA);
$tombstones = array_filter($r['body']['changes']['batches'] ?? [], static fn (array $b): bool => $b['deletedAt'] !== null);
check('delete is replicated as a tombstone', count($tombstones) === 1);

// ------------------------------------------------------------ token rotation
fwrite(STDOUT, "\nRefresh rotation and reuse detection\n");
$r = call('POST', '/v1/auth/refresh', ['refreshToken' => $refreshA]);
check('refresh issues a new pair', $r['status'] === 200 && !empty($r['body']['auth']['accessToken']));
$rotatedAccess = $r['body']['auth']['accessToken'] ?? '';
$rotatedRefresh = $r['body']['auth']['refreshToken'] ?? '';
check('rotated tokens differ', $rotatedRefresh !== $refreshA);

$r = call('GET', '/v1/profile', null, $rotatedAccess);
check('rotated access token works', $r['status'] === 200);

$r = call('POST', '/v1/auth/refresh', ['refreshToken' => $refreshA]);
check('reusing an old refresh token is refused', $r['status'] === 401 && ($r['body']['error']['code'] ?? '') === 'token_reuse_detected');

$r = call('GET', '/v1/profile', null, $rotatedAccess);
check('reuse revokes the whole family', $r['status'] === 401, 'got ' . $r['status']);

// --------------------------------------------------------------- sessions
fwrite(STDOUT, "\nSessions, password and sign-out\n");
$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => $password], null,
    ['X-Device-Name' => 'Smoke Mac', 'X-Platform' => 'macos']);
$tokenA3 = $r['body']['auth']['accessToken'] ?? '';
$r = call('GET', '/v1/auth/sessions', null, $tokenA3);
check('sessions are listed', $r['status'] === 200 && count($r['body']['sessions'] ?? []) >= 1, json_encode($r['body']));
check('current session is flagged',
    (bool) array_filter($r['body']['sessions'] ?? [], static fn (array $s): bool => $s['current'] === true));

$r = call('POST', '/v1/profile/password', ['currentPassword' => 'wrong-one', 'newPassword' => 'An0therStrongPass!'], $tokenA3);
check('password change needs the current password', $r['status'] === 401);

$newPassword = 'An0therStrongPass!' . $suffix;
$r = call('POST', '/v1/profile/password', ['currentPassword' => $password, 'newPassword' => $newPassword], $tokenA3);
check('password changed', $r['status'] === 200, json_encode($r['body']));

$r = call('GET', '/v1/profile', null, $tokenA2);
check('other sessions were revoked by the password change', $r['status'] === 401);
$r = call('GET', '/v1/profile', null, $tokenA3);
check('current session survives the password change', $r['status'] === 200);

$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => $password]);
check('old password no longer works', $r['status'] === 401);

$r = call('GET', '/v1/profile/export', null, $tokenA3);
check('data export works', $r['status'] === 200 && isset($r['body']['resources']['batches']));

$r = call('POST', '/v1/auth/logout', null, $tokenA3);
check('logout returns 200', $r['status'] === 200);
$r = call('GET', '/v1/profile', null, $tokenA3);
check('token is dead after logout', $r['status'] === 401);

// --------------------------------------------------------- account deletion
fwrite(STDOUT, "\nAccount deletion\n");
$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => $newPassword]);
$tokenA4 = $r['body']['auth']['accessToken'] ?? '';

$r = call('DELETE', '/v1/profile', ['password' => $newPassword, 'confirm' => 'nope'], $tokenA4);
check('deletion needs the exact confirmation', $r['status'] === 422);

$r = call('DELETE', '/v1/profile', ['password' => 'wrong', 'confirm' => 'DELETE'], $tokenA4);
check('deletion needs the password', $r['status'] === 401);

$r = call('DELETE', '/v1/profile', ['password' => $newPassword, 'confirm' => 'DELETE'], $tokenA4);
check('account deleted', $r['status'] === 200 && ($r['body']['status'] ?? '') === 'account_deleted');
check('deletion reports what was removed', isset($r['body']['deletedRecords']['batches']));

$r = call('GET', '/v1/profile', null, $tokenA4);
check('token is dead after deletion', $r['status'] === 401);
$r = call('POST', '/v1/auth/login', ['email' => $emailA, 'password' => $newPassword]);
check('deleted account cannot sign in', $r['status'] === 401);

// ------------------------------------------------------------- rate limiting
fwrite(STDOUT, "\nBrute-force protection\n");
$victim = "ratelimit-{$suffix}@example.test";
$limited = false;
for ($attempt = 0; $attempt < 12; $attempt++) {
    $r = call('POST', '/v1/auth/login', ['email' => $victim, 'password' => 'WrongPassword' . $attempt]);
    if ($r['status'] === 429) {
        $limited = true;
        break;
    }
}
check('repeated password guessing is rate limited', $limited, 'never returned 429');

// clean up the second account
$r = call('POST', '/v1/auth/login', ['email' => $emailB, 'password' => $password]);
$tokenB2 = $r['body']['auth']['accessToken'] ?? '';
call('DELETE', '/v1/profile', ['password' => $password, 'confirm' => 'DELETE'], $tokenB2);

// ------------------------------------------------------------------ summary
fwrite(STDOUT, "\n" . str_repeat('-', 52) . "\n");
fwrite(STDOUT, sprintf("%d passed, %d failed\n", $passed, $failed));
exit($failed === 0 ? 0 : 1);
