<?php

declare(strict_types=1);

namespace OceanCast\Domain;

use OceanCast\Core\ApiException;
use OceanCast\Core\Database;
use OceanCast\Core\Uuid;
use OceanCast\Core\Validator;

/**
 * Generic, schema-driven persistence for every household-scoped resource.
 *
 * Two invariants hold for every single query in this class:
 *   1. `household_id = :household` is always part of the WHERE clause, so one
 *      account can never read or write another account's rows.
 *   2. Column names come from the schema definition, never from user input, so
 *      no request can steer the SQL.
 */
final class ResourceRepository
{
    /** @var array<string,mixed> */
    private array $definition;

    public function __construct(public readonly string $name)
    {
        $this->definition = Schema::resource($name);
    }

    private function table(): string
    {
        return (string) $this->definition['table'];
    }

    /** @return array{field:string,column:string,type:string,max?:int} */
    private function identity(): array
    {
        /** @var array{field:string,column:string,type:string,max?:int} */
        return $this->definition['identity'];
    }

    /** @return array<string,array<string,mixed>> */
    private function fields(): array
    {
        /** @var array<string,array<string,mixed>> */
        return $this->definition['fields'];
    }

    // ------------------------------------------------------------------ read

    /**
     * @return array{items:list<array<string,mixed>>,hasMore:bool}
     */
    public function list(int $householdId, ?string $since, bool $includeDeleted, int $limit, int $offset): array
    {
        $sql = 'SELECT * FROM ' . $this->table() . ' WHERE household_id = :household';
        $params = ['household' => $householdId];

        if ($since !== null) {
            $sql .= ' AND updated_at > :since';
            $params['since'] = $since;
        }
        if (!$includeDeleted) {
            $sql .= ' AND deleted_at IS NULL';
        }

        $sql .= ' ORDER BY updated_at ASC, id ASC LIMIT :limit OFFSET :offset';
        $params['limit'] = $limit + 1;
        $params['offset'] = $offset;

        $rows = Database::all($sql, $params);
        $hasMore = count($rows) > $limit;
        if ($hasMore) {
            array_pop($rows);
        }

        return [
            'items'   => array_map(fn (array $row): array => $this->serialize($row), $rows),
            'hasMore' => $hasMore,
        ];
    }

    /**
     * When the server row was last written. Used to detect a push that is based
     * on a copy older than somebody else's edit.
     */
    public function serverUpdatedAt(int $householdId, string $identity): ?string
    {
        $row = Database::first(
            'SELECT updated_at FROM ' . $this->table() . '
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity
              LIMIT 1',
            ['household' => $householdId, 'identity' => $this->normalizeIdentity($identity)]
        );
        return $row === null ? null : (string) $row['updated_at'];
    }

    /** @return array<string,mixed>|null */
    public function find(int $householdId, string $identity): ?array
    {
        $row = Database::first(
            'SELECT * FROM ' . $this->table() . '
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity
              LIMIT 1',
            ['household' => $householdId, 'identity' => $this->normalizeIdentity($identity)]
        );
        return $row === null ? null : $this->serialize($row);
    }

    // ----------------------------------------------------------------- write

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function create(int $householdId, array $input): array
    {
        $identity = $this->readIdentity($input, generate: true);
        $existing = Database::first(
            'SELECT id, deleted_at FROM ' . $this->table() . '
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity LIMIT 1',
            ['household' => $householdId, 'identity' => $identity]
        );
        if ($existing !== null && $existing['deleted_at'] === null) {
            throw ApiException::conflict('A record with this id already exists.', 'already_exists');
        }

        return $this->write($householdId, $identity, $input, partial: false, revive: true);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function replace(int $householdId, string $identity, array $input): array
    {
        return $this->write($householdId, $this->normalizeIdentity($identity), $input, partial: false, revive: true);
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function patch(int $householdId, string $identity, array $input): array
    {
        $identity = $this->normalizeIdentity($identity);
        $current = Database::first(
            'SELECT id FROM ' . $this->table() . '
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity
                AND deleted_at IS NULL LIMIT 1',
            ['household' => $householdId, 'identity' => $identity]
        );
        if ($current === null) {
            throw ApiException::notFound('This record does not exist.');
        }
        return $this->write($householdId, $identity, $input, partial: true, revive: false);
    }

    public function softDelete(int $householdId, string $identity): bool
    {
        $now = self::now();
        $statement = Database::run(
            'UPDATE ' . $this->table() . '
                SET deleted_at = :deleted_at, updated_at = :updated_at
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity
                AND deleted_at IS NULL',
            [
                'deleted_at' => $now,
                'updated_at' => $now,
                'household'  => $householdId,
                'identity'   => $this->normalizeIdentity($identity),
            ]
        );
        return $statement->rowCount() > 0;
    }

    /**
     * Shared insert/update path used by REST writes and by bulk sync.
     *
     * @param array<string,mixed> $input
     * @return array<string,mixed>
     */
    public function write(int $householdId, string $identity, array $input, bool $partial, bool $revive): array
    {
        $columns = $this->validate($input, $partial);

        // Derived columns (product_key) are computed here, never taken from the client.
        foreach ((array) ($this->definition['derived'] ?? []) as $config) {
            $sourceField = (string) $config['from'];
            if (array_key_exists($sourceField, $input) && is_string($input[$sourceField])) {
                $columns[(string) $config['column']] = Schema::productKey($input[$sourceField]);
            }
        }

        $now = self::now();
        $existing = Database::first(
            'SELECT id, created_at FROM ' . $this->table() . '
              WHERE household_id = :household AND ' . $this->identity()['column'] . ' = :identity LIMIT 1',
            ['household' => $householdId, 'identity' => $identity]
        );

        if ($existing === null) {
            $columns['household_id'] = $householdId;
            $columns[$this->identity()['column']] = $identity;
            if ($this->identity()['column'] !== 'uuid' && $this->hasColumn('uuid')) {
                $columns['uuid'] = Uuid::v4();
            }
            $columns['created_at'] ??= $now;
            $columns['updated_at'] = $now;
            $columns['deleted_at'] = null;

            foreach ($this->fields() as $definition) {
                $column = (string) $definition['column'];
                if (!array_key_exists($column, $columns) && array_key_exists('default', $definition)) {
                    $columns[$column] = $definition['default'];
                }
            }

            $names = array_keys($columns);
            Database::run(
                'INSERT INTO ' . $this->table() . ' (' . implode(', ', $names) . ')
                 VALUES (' . implode(', ', array_map(static fn (string $c): string => ':' . $c, $names)) . ')',
                $this->bindable($columns)
            );
        } else {
            $columns['updated_at'] = $now;
            if ($revive) {
                $columns['deleted_at'] = null;
            }
            unset($columns['household_id'], $columns[$this->identity()['column']]);

            if ($columns === ['updated_at' => $now]) {
                // Nothing to change; still refresh the sync cursor.
                Database::run(
                    'UPDATE ' . $this->table() . ' SET updated_at = :now WHERE id = :id',
                    ['now' => $now, 'id' => (int) $existing['id']]
                );
            } else {
                $assignments = implode(', ', array_map(
                    static fn (string $c): string => $c . ' = :' . $c,
                    array_keys($columns)
                ));
                $params = $this->bindable($columns);
                $params['id'] = (int) $existing['id'];
                Database::run('UPDATE ' . $this->table() . ' SET ' . $assignments . ' WHERE id = :id', $params);
            }
        }

        $row = $this->find($householdId, $identity);
        if ($row === null) {
            throw new \RuntimeException('Record vanished right after it was written.');
        }
        return $row;
    }

    // ------------------------------------------------------------ validation

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed> column => value
     */
    private function validate(array $input, bool $partial): array
    {
        $validator = new Validator($input);
        $present = [];

        foreach ($this->fields() as $field => $definition) {
            $required = (bool) ($definition['required'] ?? false) && !$partial;
            $exists = array_key_exists($field, $input);

            if ($partial && !$exists) {
                continue;
            }
            // An explicit null clears an optional field.
            if ($exists && $input[$field] === null) {
                if ($required) {
                    throw ApiException::validation('Some fields need attention.', [$field => 'This field is required.']);
                }
                $present[$field] = null;
                continue;
            }
            if (!$exists && !$required) {
                continue;
            }

            match ((string) $definition['type']) {
                'string'   => $validator->string(
                    $field,
                    $required,
                    (int) ($definition['min'] ?? 0),
                    (int) ($definition['max'] ?? 255),
                    isset($definition['pattern']) ? (string) $definition['pattern'] : null
                ),
                'email'    => $validator->email($field, $required),
                'number'   => $validator->number($field, $required, (float) ($definition['min'] ?? -1e12), (float) ($definition['max'] ?? 1e12)),
                'integer'  => $validator->integer($field, $required, (int) ($definition['min'] ?? 0), (int) ($definition['max'] ?? 1000000)),
                'boolean'  => $validator->boolean($field, $required),
                'enum'     => $validator->enum($field, (array) $definition['values'], $required),
                'uuid'     => $validator->uuid($field, $required),
                'date'     => $validator->date($field, $required),
                'datetime' => $validator->dateTime($field, $required),
                'json'     => $validator->jsonValue($field, $required),
                default    => throw new \LogicException('Unknown field type in schema.'),
            };
            $present[$field] = true;
        }

        $clean = $validator->validated();
        $columns = [];

        foreach ($this->fields() as $field => $definition) {
            $column = (string) $definition['column'];
            if (array_key_exists($field, $present) && $present[$field] === null) {
                $columns[$column] = null;
                continue;
            }
            if (array_key_exists($field, $clean)) {
                $value = $clean[$field];
                if (($definition['type'] ?? '') === 'boolean') {
                    $value = $value ? 1 : 0;
                }
                $columns[$column] = $value;
            }
        }

        return $columns;
    }

    /** @param array<string,mixed> $input */
    private function readIdentity(array $input, bool $generate): string
    {
        $identity = $this->identity();
        $raw = $input[$identity['field']] ?? null;

        if ($raw === null || $raw === '') {
            if (!$generate) {
                throw ApiException::validation('Some fields need attention.', [$identity['field'] => 'This field is required.']);
            }
            if ($identity['type'] !== 'uuid') {
                throw ApiException::validation('Some fields need attention.', [$identity['field'] => 'This field is required.']);
            }
            return Uuid::v4();
        }

        if (!is_string($raw)) {
            throw ApiException::validation('Some fields need attention.', [$identity['field'] => 'This must be text.']);
        }
        return $this->normalizeIdentity($raw);
    }

    private function normalizeIdentity(string $raw): string
    {
        $identity = $this->identity();
        $value = trim($raw);

        if ($identity['type'] === 'uuid') {
            if (!Uuid::isValid($value)) {
                throw ApiException::validation('Some fields need attention.', [$identity['field'] => 'This must be a UUID.']);
            }
            return Uuid::normalize($value);
        }

        $max = (int) ($identity['max'] ?? 160);
        if ($value === '' || mb_strlen($value) > $max) {
            throw ApiException::validation('Some fields need attention.', [$identity['field'] => "Must be 1–{$max} characters."]);
        }
        if (!preg_match('/^[\p{L}\p{N}\-_.:\/ ]+$/u', $value)) {
            throw ApiException::validation('Some fields need attention.', [$identity['field'] => 'This value has an unexpected format.']);
        }
        return $value;
    }

    // ----------------------------------------------------------- serializing

    /**
     * @param array<string,mixed> $row
     * @return array<string,mixed>
     */
    public function serialize(array $row): array
    {
        $out = [$this->identity()['field'] => (string) $row[$this->identity()['column']]];

        foreach ($this->fields() as $field => $definition) {
            $column = (string) $definition['column'];
            $value = $row[$column] ?? null;

            if ($value === null) {
                $out[$field] = null;
                continue;
            }

            $out[$field] = match ((string) $definition['type']) {
                'number'   => (float) $value,
                'integer'  => (int) $value,
                'boolean'  => (bool) $value,
                'json'     => json_decode((string) $value, true),
                'date'     => (string) $value,
                'datetime' => self::iso((string) $value),
                default    => (string) $value,
            };
        }

        $out['updatedAt'] = self::iso((string) $row['updated_at'], micro: true);
        $out['deletedAt'] = $row['deleted_at'] === null ? null : self::iso((string) $row['deleted_at'], micro: true);
        if (isset($row['created_at']) && !array_key_exists('createdAt', $out)) {
            $out['createdAt'] = self::iso((string) $row['created_at']);
        }

        return $out;
    }

    private function hasColumn(string $column): bool
    {
        static $cache = [];
        $table = $this->table();
        if (!isset($cache[$table])) {
            $cache[$table] = array_column(
                Database::all('SHOW COLUMNS FROM ' . $table),
                'Field'
            );
        }
        return in_array($column, $cache[$table], true);
    }

    /** @param array<string,mixed> $columns */
    private function bindable(array $columns): array
    {
        $params = [];
        foreach ($columns as $key => $value) {
            $params[$key] = is_bool($value) ? ($value ? 1 : 0) : $value;
        }
        return $params;
    }

    /**
     * Real microsecond precision — `gmdate('u')` always returns zeroes, which
     * would collapse the sync cursor to whole seconds and lose writes that land
     * in the same second as a pull.
     */
    public static function now(): string
    {
        return (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))->format('Y-m-d H:i:s.u');
    }

    public static function iso(string $sqlDateTime, bool $micro = false): string
    {
        $timestamp = strtotime($sqlDateTime);
        if ($timestamp === false) {
            return $sqlDateTime;
        }
        if ($micro) {
            $fraction = '';
            if (preg_match('/\.(\d{1,6})/', $sqlDateTime, $matches)) {
                $fraction = '.' . str_pad($matches[1], 6, '0');
            }
            return gmdate('Y-m-d\TH:i:s', $timestamp) . $fraction . 'Z';
        }
        return gmdate('Y-m-d\TH:i:s\Z', $timestamp);
    }
}
