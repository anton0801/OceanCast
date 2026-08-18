<?php

declare(strict_types=1);

namespace OceanCast\Domain;

/**
 * Declarative description of every synced resource.
 *
 * One definition drives validation, SQL mapping and JSON output, so a field can
 * never be validated in one place and stored differently in another. Anything
 * not listed here is dropped from the request — the API is whitelist-only.
 */
final class Schema
{
    public const UNITS = ['piece', 'pack', 'gram', 'kilogram', 'milliliter', 'liter'];

    /**
     * @return array<string,array{
     *     table:string,
     *     identity:array{field:string,column:string,type:string,max?:int},
     *     fields:array<string,array<string,mixed>>,
     *     derived?:array<string,array{from:string,column:string}>
     * }>
     */
    public static function resources(): array
    {
        return [
            'zones' => [
                'table'    => 'storage_zones',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'name'      => ['column' => 'name', 'type' => 'string', 'required' => true, 'max' => 80],
                    'kind'      => ['column' => 'kind', 'type' => 'enum', 'required' => true,
                                    'values' => ['pantry', 'fridge', 'freezer', 'other']],
                    'archived'  => ['column' => 'archived', 'type' => 'boolean', 'required' => false, 'default' => false],
                    'createdAt' => ['column' => 'created_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'members' => [
                'table'    => 'members',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'name'     => ['column' => 'name', 'type' => 'string', 'required' => true, 'max' => 100],
                    'email'    => ['column' => 'email', 'type' => 'email', 'required' => false],
                    'role'     => ['column' => 'role', 'type' => 'enum', 'required' => false, 'default' => 'adult',
                                   'values' => ['owner', 'adult', 'helper']],
                    'removed'  => ['column' => 'removed', 'type' => 'boolean', 'required' => false, 'default' => false],
                    'joinedAt' => ['column' => 'joined_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'batches' => [
                'table'    => 'batches',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'derived'  => ['productKey' => ['from' => 'productName', 'column' => 'product_key']],
                'fields'   => [
                    'productName'   => ['column' => 'product_name', 'type' => 'string', 'required' => true, 'max' => 160],
                    'brand'         => ['column' => 'brand', 'type' => 'string', 'required' => false, 'max' => 120],
                    'barcode'       => ['column' => 'barcode', 'type' => 'string', 'required' => false, 'max' => 40,
                                        'pattern' => '/^[A-Za-z0-9\-]{4,40}$/'],
                    'batchCode'     => ['column' => 'batch_code', 'type' => 'string', 'required' => false, 'max' => 60],
                    'quantity'      => ['column' => 'quantity', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                    'remaining'     => ['column' => 'remaining', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                    'unit'          => ['column' => 'unit', 'type' => 'enum', 'required' => true, 'values' => self::UNITS],
                    'purchaseDate'  => ['column' => 'purchase_date', 'type' => 'date', 'required' => false],
                    'bestBefore'    => ['column' => 'best_before', 'type' => 'date', 'required' => false],
                    'reference'     => ['column' => 'reference', 'type' => 'json', 'required' => false],
                    'zoneID'        => ['column' => 'zone_uuid', 'type' => 'uuid', 'required' => false],
                    'price'         => ['column' => 'price', 'type' => 'number', 'required' => false, 'min' => 0, 'max' => 10000000],
                    'store'         => ['column' => 'store', 'type' => 'string', 'required' => false, 'max' => 120],
                    'opened'        => ['column' => 'opened', 'type' => 'boolean', 'required' => false, 'default' => false],
                    'openedAt'      => ['column' => 'opened_at', 'type' => 'datetime', 'required' => false],
                    'archived'      => ['column' => 'archived', 'type' => 'boolean', 'required' => false, 'default' => false],
                    'origin'        => ['column' => 'origin', 'type' => 'enum', 'required' => false, 'default' => 'manual',
                                        'values' => ['manual', 'scan', 'receipt', 'shopping']],
                    'photoFilename' => ['column' => 'photo_filename', 'type' => 'string', 'required' => false, 'max' => 160],
                    'notes'         => ['column' => 'notes', 'type' => 'string', 'required' => false, 'max' => 500],
                    'createdAt'     => ['column' => 'created_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'meals' => [
                'table'    => 'meals',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'name'        => ['column' => 'name', 'type' => 'string', 'required' => true, 'max' => 160],
                    'servings'    => ['column' => 'servings', 'type' => 'integer', 'required' => true, 'min' => 1, 'max' => 999],
                    'date'        => ['column' => 'date', 'type' => 'date', 'required' => false],
                    'prepMinutes' => ['column' => 'prep_minutes', 'type' => 'integer', 'required' => false, 'min' => 0, 'max' => 10000],
                    'notes'       => ['column' => 'notes', 'type' => 'string', 'required' => false, 'max' => 500],
                    'ingredients' => ['column' => 'ingredients', 'type' => 'json', 'required' => true],
                    'status'      => ['column' => 'status', 'type' => 'enum', 'required' => false, 'default' => 'planned',
                                      'values' => ['recipe', 'planned', 'cooked', 'cancelled']],
                    'archived'    => ['column' => 'archived', 'type' => 'boolean', 'required' => false, 'default' => false],
                    'cookedAt'    => ['column' => 'cooked_at', 'type' => 'datetime', 'required' => false],
                    'createdAt'   => ['column' => 'created_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'reservations' => [
                'table'    => 'reservations',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'mealID'       => ['column' => 'meal_uuid', 'type' => 'uuid', 'required' => true],
                    'ingredientID' => ['column' => 'ingredient_uuid', 'type' => 'uuid', 'required' => true],
                    'batchID'      => ['column' => 'batch_uuid', 'type' => 'uuid', 'required' => true],
                    'quantity'     => ['column' => 'quantity', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                    'createdAt'    => ['column' => 'created_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'shopping-items' => [
                'table'    => 'shopping_items',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'derived'  => ['productKey' => ['from' => 'name', 'column' => 'product_key']],
                'fields'   => [
                    'name'             => ['column' => 'name', 'type' => 'string', 'required' => true, 'max' => 160],
                    'quantity'         => ['column' => 'quantity', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                    'unit'             => ['column' => 'unit', 'type' => 'enum', 'required' => true, 'values' => self::UNITS],
                    'store'            => ['column' => 'store', 'type' => 'string', 'required' => false, 'max' => 120],
                    'targetPrice'      => ['column' => 'target_price', 'type' => 'number', 'required' => false, 'min' => 0, 'max' => 10000000],
                    'assigneeID'       => ['column' => 'assignee_uuid', 'type' => 'uuid', 'required' => false],
                    'status'           => ['column' => 'status', 'type' => 'enum', 'required' => false, 'default' => 'needed',
                                           'values' => ['needed', 'purchased', 'excluded']],
                    'sourceType'       => ['column' => 'source_type', 'type' => 'enum', 'required' => false, 'default' => 'manual',
                                           'values' => ['manual', 'mealShortfall']],
                    'sourceMealID'     => ['column' => 'source_meal_uuid', 'type' => 'uuid', 'required' => false],
                    'sourceMealName'   => ['column' => 'source_meal_name', 'type' => 'string', 'required' => false, 'max' => 160],
                    'purchasedAt'      => ['column' => 'purchased_at', 'type' => 'datetime', 'required' => false],
                    'actualQuantity'   => ['column' => 'actual_quantity', 'type' => 'number', 'required' => false, 'min' => 0, 'max' => 1000000],
                    'actualPrice'      => ['column' => 'actual_price', 'type' => 'number', 'required' => false, 'min' => 0, 'max' => 10000000],
                    'createdBatchID'   => ['column' => 'created_batch_uuid', 'type' => 'uuid', 'required' => false],
                    'excludeReason'    => ['column' => 'exclude_reason', 'type' => 'string', 'required' => false, 'max' => 255],
                    'createdAt'        => ['column' => 'created_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'prices' => [
                'table'    => 'price_entries',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'derived'  => ['productKey' => ['from' => 'productName', 'column' => 'product_key']],
                'fields'   => [
                    'productName' => ['column' => 'product_name', 'type' => 'string', 'required' => true, 'max' => 160],
                    'brand'       => ['column' => 'brand', 'type' => 'string', 'required' => false, 'max' => 120],
                    'store'       => ['column' => 'store', 'type' => 'string', 'required' => false, 'max' => 120],
                    'price'       => ['column' => 'price', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 10000000],
                    'quantity'    => ['column' => 'quantity', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                    'unit'        => ['column' => 'unit', 'type' => 'enum', 'required' => true, 'values' => self::UNITS],
                    'date'        => ['column' => 'date', 'type' => 'datetime', 'required' => true],
                    'origin'      => ['column' => 'origin', 'type' => 'enum', 'required' => false, 'default' => 'userPurchase',
                                      'values' => ['userPurchase', 'externalCatalogue']],
                    'sourceName'  => ['column' => 'source_name', 'type' => 'string', 'required' => false, 'max' => 160],
                    'sourceURL'   => ['column' => 'source_url', 'type' => 'string', 'required' => false, 'max' => 500],
                    'batchID'     => ['column' => 'batch_uuid', 'type' => 'uuid', 'required' => false],
                ],
            ],

            'activity' => [
                'table'    => 'activity_entries',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'date'           => ['column' => 'date', 'type' => 'datetime', 'required' => true],
                    'kind'           => ['column' => 'kind', 'type' => 'string', 'required' => true, 'max' => 40,
                                         'pattern' => '/^[A-Za-z]{2,40}$/'],
                    'summary'        => ['column' => 'summary', 'type' => 'string', 'required' => true, 'max' => 255],
                    'detail'         => ['column' => 'detail', 'type' => 'string', 'required' => false, 'max' => 500],
                    'batchID'        => ['column' => 'batch_uuid', 'type' => 'uuid', 'required' => false],
                    'mealID'         => ['column' => 'meal_uuid', 'type' => 'uuid', 'required' => false],
                    'shoppingItemID' => ['column' => 'shopping_item_uuid', 'type' => 'uuid', 'required' => false],
                    'alertID'        => ['column' => 'alert_id', 'type' => 'string', 'required' => false, 'max' => 60],
                    'quantityDelta'  => ['column' => 'quantity_delta', 'type' => 'number', 'required' => false,
                                         'min' => -1000000, 'max' => 1000000],
                    'unit'           => ['column' => 'unit', 'type' => 'enum', 'required' => false, 'values' => self::UNITS],
                    'reason'         => ['column' => 'reason', 'type' => 'enum', 'required' => false,
                                         'values' => ['used', 'spilled', 'corrected', 'discarded']],
                    'amount'         => ['column' => 'amount', 'type' => 'number', 'required' => false, 'min' => 0, 'max' => 10000000],
                ],
            ],

            'recall-alerts' => [
                'table'    => 'recall_alerts',
                'identity' => ['field' => 'id', 'column' => 'alert_id', 'type' => 'string', 'max' => 60],
                'fields'   => [
                    'title'              => ['column' => 'title', 'type' => 'string', 'required' => true, 'max' => 255],
                    'firmName'           => ['column' => 'firm_name', 'type' => 'string', 'required' => false, 'max' => 255],
                    'productDescription' => ['column' => 'product_description', 'type' => 'string', 'required' => true, 'max' => 8000],
                    'reason'             => ['column' => 'reason', 'type' => 'string', 'required' => false, 'max' => 8000],
                    'classification'     => ['column' => 'classification', 'type' => 'string', 'required' => false, 'max' => 60],
                    'status'             => ['column' => 'status', 'type' => 'string', 'required' => false, 'max' => 60],
                    'distribution'       => ['column' => 'distribution', 'type' => 'string', 'required' => false, 'max' => 8000],
                    'codes'              => ['column' => 'codes', 'type' => 'json', 'required' => false],
                    'reportedAt'         => ['column' => 'reported_at', 'type' => 'datetime', 'required' => false],
                    'sourceName'         => ['column' => 'source_name', 'type' => 'string', 'required' => true, 'max' => 160],
                    'sourceURL'          => ['column' => 'source_url', 'type' => 'string', 'required' => false, 'max' => 500],
                    'fetchedAt'          => ['column' => 'fetched_at', 'type' => 'datetime', 'required' => true],
                ],
            ],

            'recall-matches' => [
                'table'    => 'recall_matches',
                'identity' => ['field' => 'id', 'column' => 'uuid', 'type' => 'uuid'],
                'fields'   => [
                    'alertID'   => ['column' => 'alert_id', 'type' => 'string', 'required' => true, 'max' => 60],
                    'batchID'   => ['column' => 'batch_uuid', 'type' => 'uuid', 'required' => true],
                    'reason'    => ['column' => 'reason', 'type' => 'string', 'required' => true, 'max' => 255],
                    'decision'  => ['column' => 'decision', 'type' => 'enum', 'required' => false, 'default' => 'unconfirmed',
                                    'values' => ['unconfirmed', 'confirmed', 'notAMatch']],
                    'decidedAt' => ['column' => 'decided_at', 'type' => 'datetime', 'required' => false],
                ],
            ],

            'archived-alerts' => [
                'table'    => 'archived_alerts',
                'identity' => ['field' => 'alertID', 'column' => 'alert_id', 'type' => 'string', 'max' => 60],
                'fields'   => [
                    'reason'     => ['column' => 'reason', 'type' => 'string', 'required' => true, 'max' => 255],
                    'archivedAt' => ['column' => 'archived_at', 'type' => 'datetime', 'required' => true],
                ],
            ],

            'thresholds' => [
                'table'    => 'restock_thresholds',
                'identity' => ['field' => 'productKey', 'column' => 'product_key', 'type' => 'string', 'max' => 160],
                'fields'   => [
                    'threshold' => ['column' => 'threshold', 'type' => 'number', 'required' => true, 'min' => 0, 'max' => 1000000],
                ],
            ],
        ];
    }

    /** @return array<string,mixed> */
    public static function resource(string $name): array
    {
        $resources = self::resources();
        if (!isset($resources[$name])) {
            throw new \InvalidArgumentException('Unknown resource: ' . $name);
        }
        return $resources[$name];
    }

    /** @return string[] */
    public static function names(): array
    {
        return array_keys(self::resources());
    }

    /** Mirrors ProductKey.make() in the app so grouping matches on both sides. */
    public static function productKey(string $name): string
    {
        $normalised = mb_strtolower(trim($name));
        $folded = @iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $normalised);
        if (is_string($folded) && $folded !== '') {
            $normalised = mb_strtolower($folded);
        }
        return (string) preg_replace('/\s+/u', ' ', $normalised);
    }
}
