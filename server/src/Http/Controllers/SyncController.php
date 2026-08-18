<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Database;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Domain\Schema;
use OceanCast\Http\Auth;

/**
 * One round trip that pushes local changes and pulls everything that changed on
 * the server since the client's cursor.
 *
 * The app stays offline-first: local records remain usable without a network,
 * and sync only reconciles. Conflicts resolve last-write-wins by `updatedAt`;
 * a record the client sends with `deletedAt` becomes a tombstone so the delete
 * reaches every other device.
 */
final class SyncController
{
    private const MAX_PUSH_PER_RESOURCE = 500;
    private const MAX_PULL_PER_RESOURCE = 500;

    public function sync(Request $request, Auth $auth): Response
    {
        $body = $request->json();
        $householdId = $auth->householdId();

        // A household can be created in the same round trip as the first push.
        if (isset($body['household']) && is_array($body['household'])) {
            HouseholdController::upsert($body['household'], $auth, $request->ip);
            $householdId = $auth->householdId();
        }

        if ($householdId === null) {
            throw ApiException::conflict(
                'This account has no household yet. Send it in `household` or via PUT /v1/household.',
                'household_required'
            );
        }

        $since = null;
        if (isset($body['since']) && is_string($body['since']) && $body['since'] !== '') {
            $timestamp = strtotime($body['since']);
            if ($timestamp === false) {
                throw ApiException::validation('Some fields need attention.', ['since' => 'Use an ISO-8601 timestamp.']);
            }
            $fraction = '';
            if (preg_match('/\.(\d{1,6})/', $body['since'], $matches)) {
                $fraction = '.' . str_pad($matches[1], 6, '0');
            }
            $since = gmdate('Y-m-d H:i:s', $timestamp) . $fraction;
        }

        $applied = [];
        $rejected = [];
        $conflicts = [];

        $changes = $body['changes'] ?? [];
        if (!is_array($changes)) {
            throw ApiException::validation('Some fields need attention.', ['changes' => 'This must be an object.']);
        }

        foreach ($changes as $resourceName => $records) {
            if (!in_array($resourceName, Schema::names(), true)) {
                throw ApiException::validation('Unknown resource in changes.', ['changes' => 'Unknown resource: ' . (string) $resourceName]);
            }
            if (!is_array($records)) {
                throw ApiException::validation('Some fields need attention.', ['changes' => $resourceName . ' must be an array.']);
            }
            if (count($records) > self::MAX_PUSH_PER_RESOURCE) {
                throw ApiException::validation(
                    'Too many records in one push.',
                    ['changes' => $resourceName . ' is limited to ' . self::MAX_PUSH_PER_RESOURCE . ' records per request.']
                );
            }

            $repository = new ResourceRepository($resourceName);
            $identityField = Schema::resource($resourceName)['identity']['field'];
            $count = 0;

            foreach ($records as $record) {
                if (!is_array($record)) {
                    $rejected[] = ['resource' => $resourceName, 'id' => null, 'reason' => 'Record must be an object.'];
                    continue;
                }
                $identity = isset($record[$identityField]) && is_string($record[$identityField])
                    ? $record[$identityField]
                    : null;

                // Conflict rule: if this row changed on the server after the
                // client's cursor, the client is pushing a stale copy. Keep the
                // server version and let the pull below hand it back — a silent
                // overwrite would lose somebody else's edit.
                if ($since !== null && $identity !== null) {
                    $serverUpdatedAt = $repository->serverUpdatedAt($householdId, $identity);
                    if ($serverUpdatedAt !== null && $serverUpdatedAt > $since) {
                        $conflicts[] = [
                            'resource' => $resourceName,
                            'id'       => $identity,
                            'reason'   => 'Changed on another device after your last sync. The server version was kept and is included in this response.',
                        ];
                        continue;
                    }
                }

                try {
                    Database::transaction(function () use ($repository, $householdId, $record, $identity, $resourceName, &$count): void {
                        if ($identity === null) {
                            $repository->create($householdId, $record);
                        } elseif (!empty($record['deletedAt'])) {
                            $repository->write($householdId, $identity, self::withoutTombstoneFields($record), partial: true, revive: false);
                            $repository->softDelete($householdId, $identity);
                        } else {
                            $repository->write($householdId, $identity, $record, partial: false, revive: true);
                        }
                        $count++;
                    });
                } catch (ApiException $error) {
                    $rejected[] = [
                        'resource' => $resourceName,
                        'id'       => $identity,
                        'reason'   => $error->getMessage(),
                        'fields'   => $error->fields,
                    ];
                }
            }
            $applied[$resourceName] = $count;
        }

        if (isset($body['settings']) && is_array($body['settings'])) {
            $encoded = json_encode($body['settings'], JSON_UNESCAPED_UNICODE);
            if ($encoded !== false && strlen($encoded) <= 16384) {
                Database::run(
                    'INSERT INTO user_settings (user_id, settings, updated_at)
                     VALUES (:user_id, :settings, :now)
                     ON DUPLICATE KEY UPDATE settings = VALUES(settings), updated_at = VALUES(updated_at)',
                    ['user_id' => $auth->userId(), 'settings' => $encoded, 'now' => ResourceRepository::now()]
                );
            }
        }

        // Pull phase. The cursor is the server clock, taken *before* reading, so a
        // write landing mid-request is picked up by the next sync instead of lost.
        $serverTime = ResourceRepository::now();
        $pulled = [];
        $hasMore = false;

        foreach (Schema::names() as $name) {
            $repository = new ResourceRepository($name);
            $result = $repository->list($householdId, $since, includeDeleted: true, limit: self::MAX_PULL_PER_RESOURCE, offset: 0);
            $pulled[$name] = $result['items'];
            $hasMore = $hasMore || $result['hasMore'];
        }

        $householdRow = Database::first('SELECT * FROM households WHERE id = :id', ['id' => $householdId]);
        $settingsRow = Database::first('SELECT settings, updated_at FROM user_settings WHERE user_id = :id', ['id' => $auth->userId()]);

        return Response::ok([
            'serverTime' => ResourceRepository::iso($serverTime, true),
            'household'  => $householdRow === null ? null : HouseholdController::serializeHousehold($householdRow),
            'settings'   => $settingsRow === null ? null : json_decode((string) $settingsRow['settings'], true),
            // Cast to object so an empty map encodes as {} and not [] — a typed
            // client cannot decode a dictionary from a JSON array.
            'applied'    => (object) $applied,
            'rejected'   => $rejected,
            'conflicts'  => $conflicts,
            'changes'    => (object) $pulled,
            'hasMore'    => $hasMore,
        ]);
    }

    /** @param array<string,mixed> $record @return array<string,mixed> */
    private static function withoutTombstoneFields(array $record): array
    {
        unset($record['deletedAt'], $record['updatedAt']);
        return $record;
    }
}
