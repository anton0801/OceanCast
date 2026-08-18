<?php

declare(strict_types=1);

namespace OceanCast\Http;

use OceanCast\Core\ApiException;
use OceanCast\Core\Database;

/**
 * The authenticated caller for the current request. Controllers never read the
 * token themselves — they ask this object, which is only ever built after the
 * bearer token has been verified.
 */
final class Auth
{
    private ?int $householdId = null;
    private bool $householdResolved = false;

    /**
     * @param array<string,mixed> $user
     * @param array<string,mixed> $token
     */
    public function __construct(
        public readonly array $user,
        public readonly array $token,
    ) {
    }

    public function userId(): int
    {
        return (int) $this->user['id'];
    }

    public function tokenId(): int
    {
        return (int) $this->token['id'];
    }

    /** The household this account may read and write, or null when none exists yet. */
    public function householdId(): ?int
    {
        if ($this->householdResolved) {
            return $this->householdId;
        }
        $this->householdResolved = true;

        $row = Database::first(
            'SELECT h.id
               FROM households h
               JOIN household_access a ON a.household_id = h.id
              WHERE a.user_id = :user_id AND h.deleted_at IS NULL
              ORDER BY h.id ASC
              LIMIT 1',
            ['user_id' => $this->userId()]
        );

        $this->householdId = $row === null ? null : (int) $row['id'];
        return $this->householdId;
    }

    /** Same as householdId(), but refuses the request instead of returning null. */
    public function requireHouseholdId(): int
    {
        $id = $this->householdId();
        if ($id === null) {
            throw ApiException::conflict(
                'This account has no household yet. Send PUT /v1/household first.',
                'household_required'
            );
        }
        return $id;
    }

    public function forgetHousehold(): void
    {
        $this->householdResolved = false;
        $this->householdId = null;
    }

    /** @return array<string,mixed> */
    public function publicUser(): array
    {
        return [
            'id'          => (string) $this->user['uuid'],
            'email'       => (string) $this->user['email'],
            'displayName' => (string) $this->user['displayName'],
            'createdAt'   => \OceanCast\Domain\ResourceRepository::iso((string) $this->user['createdAt']),
        ];
    }
}
