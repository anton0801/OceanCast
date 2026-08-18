<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Core\Validator;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Domain\Schema;
use OceanCast\Http\Auth;
use OceanCast\Security\AuditLog;
use OceanCast\Security\Passwords;
use OceanCast\Security\RateLimiter;
use OceanCast\Security\TokenService;

final class ProfileController
{
    public function show(Request $request, Auth $auth): Response
    {
        $householdId = $auth->householdId();
        $stats = ['household' => null, 'records' => []];

        if ($householdId !== null) {
            $household = Database::first(
                'SELECT uuid, name, currency_code, created_at FROM households WHERE id = :id',
                ['id' => $householdId]
            );
            if ($household !== null) {
                $stats['household'] = [
                    'id'           => (string) $household['uuid'],
                    'name'         => (string) $household['name'],
                    'currencyCode' => (string) $household['currency_code'],
                    'createdAt'    => ResourceRepository::iso((string) $household['created_at']),
                ];
            }
            foreach (Schema::names() as $name) {
                $table = Schema::resource($name)['table'];
                $row = Database::first(
                    'SELECT COUNT(*) AS total FROM ' . $table . '
                      WHERE household_id = :household AND deleted_at IS NULL',
                    ['household' => $householdId]
                );
                $stats['records'][$name] = (int) ($row['total'] ?? 0);
            }
        }

        $sessions = TokenService::sessions($auth->userId(), $auth->tokenId());

        return Response::ok([
            'user'         => $auth->publicUser(),
            'household'    => $stats['household'],
            'records'      => (object) $stats['records'],
            'sessionCount' => count($sessions),
        ]);
    }

    public function update(Request $request, Auth $auth): Response
    {
        $input = $request->json();
        $validator = new Validator($input);

        if ($validator->has('displayName')) {
            $validator->string('displayName', true, 1, 100);
        }
        if ($validator->has('email')) {
            $validator->email('email');
            $validator->string('currentPassword', true, 1, 200);
        }
        $data = $validator->validated();

        if ($data === []) {
            throw ApiException::validation('Nothing to update.', ['displayName' => 'Send displayName or email.']);
        }

        $user = Database::first('SELECT * FROM users WHERE id = :id', ['id' => $auth->userId()]);
        if ($user === null) {
            throw ApiException::unauthorized('This account no longer exists.', 'account_inactive');
        }

        $updates = ['now' => ResourceRepository::now(), 'id' => $auth->userId()];
        $assignments = ['updated_at = :now'];

        if (isset($data['displayName'])) {
            $assignments[] = 'display_name = :display_name';
            $updates['display_name'] = $data['displayName'];
        }

        if (isset($data['email'])) {
            RateLimiter::hit('email-change:user', (string) $auth->userId(), 5, 3600);

            if (!Passwords::verify($data['currentPassword'], (string) $user['password_hash'])) {
                AuditLog::record($auth->userId(), 'email_change_denied', null, $request->ip);
                throw ApiException::unauthorized('Your current password is incorrect.', 'invalid_credentials');
            }
            if (strtolower((string) $user['email']) !== $data['email']) {
                $taken = Database::first(
                    'SELECT id FROM users WHERE email = :email AND id <> :id LIMIT 1',
                    ['email' => $data['email'], 'id' => $auth->userId()]
                );
                if ($taken !== null) {
                    throw ApiException::conflict('This email cannot be used.', 'email_unavailable');
                }
                $assignments[] = 'email = :email';
                $assignments[] = 'email_hash = :email_hash';
                $updates['email'] = $data['email'];
                $updates['email_hash'] = AuthController::emailHash($data['email']);
            }
        }

        Database::run('UPDATE users SET ' . implode(', ', $assignments) . ' WHERE id = :id', $updates);
        AuditLog::record($auth->userId(), 'profile_updated', implode(',', array_keys($data)), $request->ip);

        $fresh = Database::first('SELECT uuid, email, display_name, created_at FROM users WHERE id = :id', ['id' => $auth->userId()]);

        return Response::ok([
            'user' => [
                'id'          => (string) $fresh['uuid'],
                'email'       => (string) $fresh['email'],
                'displayName' => (string) $fresh['display_name'],
                'createdAt'   => ResourceRepository::iso((string) $fresh['created_at']),
            ],
        ]);
    }

    public function changePassword(Request $request, Auth $auth): Response
    {
        RateLimiter::hit('password-change:user', (string) $auth->userId(), 5, 900);

        $data = (new Validator($request->json()))
            ->string('currentPassword', true, 1, 200)
            ->password('newPassword')
            ->validated();

        $user = Database::first('SELECT password_hash FROM users WHERE id = :id', ['id' => $auth->userId()]);
        if ($user === null || !Passwords::verify($data['currentPassword'], (string) $user['password_hash'])) {
            AuditLog::record($auth->userId(), 'password_change_denied', null, $request->ip);
            throw ApiException::unauthorized('Your current password is incorrect.', 'invalid_credentials');
        }
        if (Passwords::verify($data['newPassword'], (string) $user['password_hash'])) {
            throw ApiException::validation('Choose a different password.', ['newPassword' => 'This is your current password.']);
        }

        $now = ResourceRepository::now();
        Database::run(
            'UPDATE users SET password_hash = :hash, password_changed_at = :changed_at, updated_at = :updated_at
              WHERE id = :id',
            [
                'hash'       => Passwords::hash($data['newPassword']),
                'changed_at' => $now,
                'updated_at' => $now,
                'id'         => $auth->userId(),
            ]
        );

        // A password change ends every other session; the current device stays in.
        $revoked = TokenService::revokeAllForUser($auth->userId(), 'password_changed', $auth->tokenId());
        AuditLog::record($auth->userId(), 'password_changed', $revoked . ' session(s) revoked', $request->ip);

        return Response::ok(['status' => 'password_changed', 'revokedSessions' => $revoked]);
    }

    /** Full export of everything stored for this account. */
    public function export(Request $request, Auth $auth): Response
    {
        RateLimiter::hit('export:user', (string) $auth->userId(), 10, 3600);

        $payload = [
            'exportedAt' => gmdate('c'),
            'user'       => $auth->publicUser(),
            'household'  => null,
            'resources'  => [],
        ];

        $householdId = $auth->householdId();
        if ($householdId !== null) {
            $household = Database::first('SELECT * FROM households WHERE id = :id', ['id' => $householdId]);
            if ($household !== null) {
                $payload['household'] = HouseholdController::serializeHousehold($household);
            }
            foreach (Schema::names() as $name) {
                $repository = new ResourceRepository($name);
                $rows = Database::all(
                    'SELECT * FROM ' . Schema::resource($name)['table'] . ' WHERE household_id = :household',
                    ['household' => $householdId]
                );
                $payload['resources'][$name] = array_map(
                    static fn (array $row): array => $repository->serialize($row),
                    $rows
                );
            }
        }

        AuditLog::record($auth->userId(), 'data_exported', null, $request->ip);
        return Response::ok($payload);
    }

    /**
     * Hard delete. Password confirmation is mandatory and the cascade removes the
     * household with everything in it — nothing is left behind for later.
     */
    public function destroy(Request $request, Auth $auth): Response
    {
        RateLimiter::hit('delete-account:user', (string) $auth->userId(), 5, 3600);

        $input = $request->json();
        $data = (new Validator($input))
            ->string('password', true, 1, 200)
            ->string('confirm', true, 1, 20)
            ->validated();

        if ($data['confirm'] !== 'DELETE') {
            throw ApiException::validation(
                'Confirmation is required.',
                ['confirm' => 'Send confirm = "DELETE" to proceed.']
            );
        }

        $user = Database::first('SELECT password_hash FROM users WHERE id = :id', ['id' => $auth->userId()]);
        if ($user === null || !Passwords::verify($data['password'], (string) $user['password_hash'])) {
            AuditLog::record($auth->userId(), 'account_delete_denied', null, $request->ip);
            throw ApiException::unauthorized('Your password is incorrect.', 'invalid_credentials');
        }

        $householdId = $auth->householdId();
        $removed = [];
        if ($householdId !== null) {
            foreach (Schema::names() as $name) {
                $row = Database::first(
                    'SELECT COUNT(*) AS total FROM ' . Schema::resource($name)['table'] . ' WHERE household_id = :household',
                    ['household' => $householdId]
                );
                $removed[$name] = (int) ($row['total'] ?? 0);
            }
        }

        Database::transaction(static function () use ($auth): void {
            TokenService::revokeAllForUser($auth->userId(), 'account_deleted');
            // FK cascades clear households, access rows and every household-scoped table.
            Database::run('DELETE FROM users WHERE id = :id', ['id' => $auth->userId()]);
        });

        AuditLog::record(null, 'account_deleted', 'user ' . $auth->user['uuid'], $request->ip);

        return Response::ok([
            'status'         => 'account_deleted',
            'deletedRecords' => (object) $removed,
            'note'           => 'Every session was revoked and all server-side data for this account was removed.',
        ]);
    }
}
