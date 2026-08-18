<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Domain\Schema;
use OceanCast\Http\Auth;

/**
 * REST CRUD for every synced resource:
 *
 *   GET    /v1/{resource}            list (supports ?since= for delta pulls)
 *   POST   /v1/{resource}            create
 *   GET    /v1/{resource}/{id}       read one
 *   PUT    /v1/{resource}/{id}       create or replace (idempotent)
 *   PATCH  /v1/{resource}/{id}       partial update
 *   DELETE /v1/{resource}/{id}       soft delete (tombstone for other devices)
 */
final class ResourceController
{
    private const MAX_LIMIT = 500;

    /** @param array<string,string> $params */
    public function index(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        $householdId = $auth->requireHouseholdId();

        $limit = max(1, min(self::MAX_LIMIT, $request->queryInt('limit', 200)));
        $offset = max(0, $request->queryInt('offset', 0));
        $since = self::sinceParam($request);
        $includeDeleted = in_array($request->queryString('includeDeleted', '0'), ['1', 'true'], true);

        $result = $repository->list($householdId, $since, $includeDeleted, $limit, $offset);

        return Response::ok([
            'resource'   => $repository->name,
            'items'      => $result['items'],
            'hasMore'    => $result['hasMore'],
            'limit'      => $limit,
            'offset'     => $offset,
            'serverTime' => ResourceRepository::iso(ResourceRepository::now(), true),
        ]);
    }

    /** @param array<string,string> $params */
    public function store(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        $householdId = $auth->requireHouseholdId();
        $record = $repository->create($householdId, $request->json());

        return Response::created(['item' => $record]);
    }

    /** @param array<string,string> $params */
    public function show(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        $record = $repository->find($auth->requireHouseholdId(), $params['id'] ?? '');
        if ($record === null || $record['deletedAt'] !== null) {
            throw ApiException::notFound('This record does not exist.');
        }
        return Response::ok(['item' => $record]);
    }

    /** @param array<string,string> $params */
    public function replace(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        $record = $repository->replace($auth->requireHouseholdId(), $params['id'] ?? '', $request->json());
        return Response::ok(['item' => $record]);
    }

    /** @param array<string,string> $params */
    public function patch(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        $record = $repository->patch($auth->requireHouseholdId(), $params['id'] ?? '', $request->json());
        return Response::ok(['item' => $record]);
    }

    /** @param array<string,string> $params */
    public function destroy(Request $request, Auth $auth, array $params): Response
    {
        $repository = self::repository($params);
        if (!$repository->softDelete($auth->requireHouseholdId(), $params['id'] ?? '')) {
            throw ApiException::notFound('This record does not exist, or was already deleted.');
        }
        return Response::ok(['status' => 'deleted', 'id' => $params['id'] ?? '']);
    }

    /** @param array<string,string> $params */
    private static function repository(array $params): ResourceRepository
    {
        $name = $params['resource'] ?? '';
        if (!in_array($name, Schema::names(), true)) {
            throw ApiException::notFound('Unknown resource: ' . htmlspecialchars($name, ENT_QUOTES));
        }
        return new ResourceRepository($name);
    }

    public static function sinceParam(Request $request): ?string
    {
        $since = $request->queryString('since');
        if ($since === null) {
            return null;
        }
        $timestamp = strtotime($since);
        if ($timestamp === false) {
            throw ApiException::validation('Some fields need attention.', ['since' => 'Use an ISO-8601 timestamp.']);
        }
        $fraction = '';
        if (preg_match('/\.(\d{1,6})/', $since, $matches)) {
            $fraction = '.' . str_pad($matches[1], 6, '0');
        }
        return gmdate('Y-m-d H:i:s', $timestamp) . $fraction;
    }
}
