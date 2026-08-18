<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Database;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Core\Uuid;
use OceanCast\Core\Validator;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Http\Auth;
use OceanCast\Security\AuditLog;

/**
 * The household is a singleton per account in this version: /v1/household.
 * Creating it is idempotent — the app sends the UUID it already generated
 * locally, so the same household is never created twice.
 */
final class HouseholdController
{
    public function show(Request $request, Auth $auth): Response
    {
        $householdId = $auth->householdId();
        if ($householdId === null) {
            return Response::ok(['household' => null]);
        }
        $row = Database::first('SELECT * FROM households WHERE id = :id', ['id' => $householdId]);
        return Response::ok(['household' => $row === null ? null : self::serializeHousehold($row)]);
    }

    public function replace(Request $request, Auth $auth): Response
    {
        return Response::ok(['household' => self::upsert($request->json(), $auth, $request->ip)]);
    }

    /**
     * Shared by PUT /v1/household and by the bulk sync endpoint, so both paths
     * validate and write identically.
     *
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public static function upsert(array $input, Auth $auth, string $ip): array
    {
        $data = (new Validator($input))
            ->uuid('id', true)
            ->string('name', true, 1, 120)
            ->string('currencyCode', true, 3, 3, '/^[A-Za-z]{3}$/')
            ->jsonValue('preferences', false, 8192)
            ->validated();

        $now = ResourceRepository::now();
        $existingForUser = $auth->householdId();

        $byUuid = Database::first(
            'SELECT * FROM households WHERE uuid = :uuid LIMIT 1',
            ['uuid' => $data['id']]
        );

        // A UUID that belongs to somebody else must never be adopted.
        if ($byUuid !== null && (int) $byUuid['owner_user_id'] !== $auth->userId()) {
            $hasAccess = Database::first(
                'SELECT id FROM household_access WHERE household_id = :household AND user_id = :user LIMIT 1',
                ['household' => (int) $byUuid['id'], 'user' => $auth->userId()]
            );
            if ($hasAccess === null) {
                throw ApiException::forbidden('This household belongs to another account.');
            }
        }

        if ($byUuid === null && $existingForUser !== null) {
            // The account already has a household under a different UUID: rename it
            // rather than creating a second one (one household per account for now).
            Database::run(
                'UPDATE households SET name = :name, currency_code = :currency, preferences = :preferences,
                        updated_at = :now, deleted_at = NULL
                  WHERE id = :id',
                [
                    'name'        => $data['name'],
                    'currency'    => strtoupper($data['currencyCode']),
                    'preferences' => $data['preferences'] ?? null,
                    'now'         => $now,
                    'id'          => $existingForUser,
                ]
            );
            $row = Database::first('SELECT * FROM households WHERE id = :id', ['id' => $existingForUser]);
            return self::serializeHousehold($row ?? []);
        }

        if ($byUuid === null) {
            Database::transaction(static function () use ($data, $auth, $now): void {
                Database::run(
                    'INSERT INTO households (uuid, owner_user_id, name, currency_code, preferences, created_at, updated_at)
                     VALUES (:uuid, :owner, :name, :currency, :preferences, :created_at, :updated_at)',
                    [
                        'uuid'        => $data['id'],
                        'owner'       => $auth->userId(),
                        'name'        => $data['name'],
                        'currency'    => strtoupper($data['currencyCode']),
                        'preferences' => $data['preferences'] ?? null,
                        'created_at'  => $now,
                        'updated_at'  => $now,
                    ]
                );
                $householdId = (int) Database::pdo()->lastInsertId();
                Database::run(
                    'INSERT INTO household_access (household_id, user_id, role, created_at)
                     VALUES (:household, :user, :role, :now)
                     ON DUPLICATE KEY UPDATE role = VALUES(role)',
                    ['household' => $householdId, 'user' => $auth->userId(), 'role' => 'owner', 'now' => $now]
                );
            });
            $auth->forgetHousehold();
            AuditLog::record($auth->userId(), 'household_created', $data['id'], $ip);
        } else {
            Database::run(
                'UPDATE households SET name = :name, currency_code = :currency, preferences = :preferences,
                        updated_at = :now, deleted_at = NULL
                  WHERE id = :id',
                [
                    'name'        => $data['name'],
                    'currency'    => strtoupper($data['currencyCode']),
                    'preferences' => $data['preferences'] ?? null,
                    'now'         => $now,
                    'id'          => (int) $byUuid['id'],
                ]
            );
        }

        $row = Database::first('SELECT * FROM households WHERE uuid = :uuid', ['uuid' => $data['id']]);
        $auth->forgetHousehold();
        return $row === null ? [] : self::serializeHousehold($row);
    }

    /** Wipes the household and everything inside it, but keeps the account. */
    public function destroy(Request $request, Auth $auth): Response
    {
        $householdId = $auth->requireHouseholdId();

        $row = Database::first('SELECT uuid, owner_user_id FROM households WHERE id = :id', ['id' => $householdId]);
        if ($row === null) {
            throw ApiException::notFound('No household to delete.');
        }
        if ((int) $row['owner_user_id'] !== $auth->userId()) {
            throw ApiException::forbidden('Only the owner can delete this household.');
        }

        $data = (new Validator($request->json()))
            ->string('confirm', true, 1, 20)
            ->validated();
        if ($data['confirm'] !== 'DELETE') {
            throw ApiException::validation('Confirmation is required.', ['confirm' => 'Send confirm = "DELETE".']);
        }

        Database::run('DELETE FROM households WHERE id = :id', ['id' => $householdId]);
        $auth->forgetHousehold();
        AuditLog::record($auth->userId(), 'household_deleted', (string) $row['uuid'], $request->ip);

        return Response::ok(['status' => 'household_deleted']);
    }

    // ---------------------------------------------------------------- settings

    public function showSettings(Request $request, Auth $auth): Response
    {
        $row = Database::first('SELECT settings, updated_at FROM user_settings WHERE user_id = :id', ['id' => $auth->userId()]);
        return Response::ok([
            'settings'  => $row === null ? null : json_decode((string) $row['settings'], true),
            'updatedAt' => $row === null ? null : ResourceRepository::iso((string) $row['updated_at'], true),
        ]);
    }

    public function replaceSettings(Request $request, Auth $auth): Response
    {
        $data = (new Validator($request->json()))
            ->jsonValue('settings', true, 16384)
            ->validated();

        $now = ResourceRepository::now();
        Database::run(
            'INSERT INTO user_settings (user_id, settings, updated_at)
             VALUES (:user_id, :settings, :now)
             ON DUPLICATE KEY UPDATE settings = VALUES(settings), updated_at = VALUES(updated_at)',
            ['user_id' => $auth->userId(), 'settings' => $data['settings'], 'now' => $now]
        );

        return Response::ok([
            'settings'  => json_decode($data['settings'], true),
            'updatedAt' => ResourceRepository::iso($now, true),
        ]);
    }

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public static function serializeHousehold(array $row): array
    {
        return [
            'id'           => (string) ($row['uuid'] ?? ''),
            'name'         => (string) ($row['name'] ?? ''),
            'currencyCode' => (string) ($row['currency_code'] ?? 'USD'),
            'preferences'  => isset($row['preferences']) && $row['preferences'] !== null
                ? json_decode((string) $row['preferences'], true)
                : null,
            'createdAt'    => isset($row['created_at']) ? ResourceRepository::iso((string) $row['created_at']) : null,
            'updatedAt'    => isset($row['updated_at']) ? ResourceRepository::iso((string) $row['updated_at'], true) : null,
        ];
    }
}
