<?php

declare(strict_types=1);

namespace OceanCast\Http\Controllers;

use OceanCast\Core\ApiException;
use OceanCast\Core\Config;
use OceanCast\Core\Database;
use OceanCast\Core\OutboundHttp;
use OceanCast\Core\PayloadCipher;
use OceanCast\Core\Request;
use OceanCast\Core\Response;
use OceanCast\Domain\ResourceRepository;
use OceanCast\Http\Auth;

/**
 * Device attribution collected before sign-in.
 *
 *   POST /v1/beacon          the facts available the moment the app opens
 *   POST /v1/beacon/resolve  conversion + advertising id; forwards outward and,
 *                            when the offer is granted, answers with the
 *                            `analytics-service` header that opens the splash
 *   POST /v1/beacon/link     ties the signed-in account to the device key
 *
 * The JSON keys the app sends ("ref", "sys", "pkg", …) are specific to this app;
 * they are mapped here onto fixed internal columns, and forwarded to the
 * external service under the fixed names that service expects.
 */
final class BeaconController
{
    /** wire key => internal column */
    private const FIELD_MAP = [
        'ref'     => 'ref',
        'sys'     => 'os',
        'pkg'     => 'bundle_id',
        'proj'    => 'firebase_project_id',
        'listing' => 'store_id',
        'pushId'  => 'push_token',
        'locale'  => 'locale',
        'adTag'   => 'idfa',
    ];

    public function collect(Request $request): Response
    {
        $input = $this->readPayload($request);
        $device = $this->extract($input);

        $this->upsertDevice($device, $request->ip, countsAsLaunch: true);
        $this->storeAttribution($device['ref'], $this->conversion($input));

        return Response::ok(['status' => 'ok']);
    }

    public function resolve(Request $request): Response
    {
        $input = $this->readPayload($request);
        $device = $this->extract($input);
        $conversion = $this->conversion($input);

        if ($conversion !== null) {
            $summary = $this->summarize($conversion);
            $device['attribution_status'] = $summary['status'];
            $device['media_source'] = $summary['media_source'];
            $device['campaign'] = $summary['campaign'];
        }

        $this->upsertDevice($device, $request->ip, countsAsLaunch: false);
        $this->storeAttribution($device['ref'], $conversion);

        $gate = $this->forward($device, $conversion, $request->ip);

        $headers = [];
        if ($gate['hasOffer']) {
            $headers['analytics-service'] = $gate['url'];
        }

        return new Response(200, [
            'authorized' => $gate['hasOffer'],
            'account'    => $gate['account'],
        ], $headers);
    }

    public function link(Request $request, Auth $auth): Response
    {
        $ref = $this->cleanRef($request->json()['ref'] ?? null);
        if ($ref === null) {
            throw ApiException::validation('Some fields need attention.', ['ref' => 'This field is required.']);
        }
        Database::run(
            'INSERT IGNORE INTO device_accounts (ref, user_id, created_at)
             VALUES (:ref, :user, :now)',
            ['ref' => $ref, 'user' => $auth->userId(), 'now' => ResourceRepository::now()]
        );
        return Response::ok(['status' => 'linked']);
    }

    // --------------------------------------------------------------- payload

    /** @return array<string,mixed> */
    private function readPayload(Request $request): array
    {
        $body = $request->json();

        if (isset($body['sealed']) && is_string($body['sealed'])) {
            $plain = PayloadCipher::open($body['sealed']);
            if ($plain === null) {
                throw ApiException::badRequest('The payload could not be read.', 'invalid_payload');
            }
            $decoded = json_decode($plain, true);
            if (!is_array($decoded)) {
                throw ApiException::badRequest('The payload could not be read.', 'invalid_payload');
            }
            return $decoded;
        }

        // A configured key in production means encryption is mandatory.
        if (PayloadCipher::isConfigured() && Config::isProduction()) {
            throw ApiException::badRequest('An encrypted payload is required.', 'payload_required');
        }
        return $body;
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,string|null> internal column => value (ref always set)
     */
    private function extract(array $input): array
    {
        $device = [];
        foreach (self::FIELD_MAP as $wire => $column) {
            $device[$column] = $this->cleanString($input[$wire] ?? null, $column === 'push_token' ? 512 : 191);
        }

        $device['ref'] = $this->cleanRef($input['ref'] ?? null);
        if ($device['ref'] === null) {
            throw ApiException::validation('Some fields need attention.', ['ref' => 'A device reference is required.']);
        }
        return $device;
    }

    /**
     * @param array<string,mixed> $input
     * @return array<string,mixed>|null the full conversion object
     */
    private function conversion(array $input): ?array
    {
        $raw = $input['attr'] ?? null;
        if (!is_array($raw) || $raw === []) {
            return null;
        }
        return $raw;
    }

    // ---------------------------------------------------------------- device

    /** @param array<string,string|null> $device */
    private function upsertDevice(array $device, string $sourceIp, bool $countsAsLaunch): void
    {
        $now = ResourceRepository::now();
        $step = $countsAsLaunch ? 1 : 0;

        Database::run(
            'INSERT INTO devices
                (ref, os, bundle_id, firebase_project_id, store_id, push_token, locale, idfa,
                 attribution_status, media_source, campaign, source_ip,
                 launch_count, first_seen_at, last_seen_at, created_at, updated_at)
             VALUES
                (:ref, :os, :bundle_id, :firebase_project_id, :store_id, :push_token, :locale, :idfa,
                 :attribution_status, :media_source, :campaign, :source_ip,
                 :launch_init, :first_seen, :last_seen, :created, :updated)
             ON DUPLICATE KEY UPDATE
                os                  = COALESCE(NULLIF(VALUES(os), \'\'), devices.os),
                bundle_id           = COALESCE(NULLIF(VALUES(bundle_id), \'\'), devices.bundle_id),
                firebase_project_id = COALESCE(NULLIF(VALUES(firebase_project_id), \'\'), devices.firebase_project_id),
                store_id            = COALESCE(NULLIF(VALUES(store_id), \'\'), devices.store_id),
                push_token          = COALESCE(NULLIF(VALUES(push_token), \'\'), devices.push_token),
                locale              = COALESCE(NULLIF(VALUES(locale), \'\'), devices.locale),
                idfa                = COALESCE(NULLIF(VALUES(idfa), \'\'), devices.idfa),
                attribution_status  = COALESCE(NULLIF(VALUES(attribution_status), \'\'), devices.attribution_status),
                media_source        = COALESCE(NULLIF(VALUES(media_source), \'\'), devices.media_source),
                campaign            = COALESCE(NULLIF(VALUES(campaign), \'\'), devices.campaign),
                source_ip           = COALESCE(NULLIF(VALUES(source_ip), \'\'), devices.source_ip),
                launch_count        = devices.launch_count + :launch_step,
                last_seen_at        = VALUES(last_seen_at),
                updated_at          = VALUES(updated_at)',
            [
                'ref'                 => $device['ref'],
                'os'                  => $device['os'],
                'bundle_id'           => $device['bundle_id'],
                'firebase_project_id' => $device['firebase_project_id'],
                'store_id'            => $device['store_id'],
                'push_token'          => $device['push_token'],
                'locale'              => $device['locale'],
                'idfa'                => $device['idfa'],
                'attribution_status'  => $device['attribution_status'] ?? null,
                'media_source'        => $device['media_source'] ?? null,
                'campaign'            => $device['campaign'] ?? null,
                'source_ip'           => $sourceIp,
                'launch_init'         => $step,
                'first_seen'          => $now,
                'last_seen'           => $now,
                'created'             => $now,
                'updated'             => $now,
                'launch_step'         => $step,
            ]
        );
    }

    /** @param array<string,mixed>|null $conversion */
    private function storeAttribution(string $ref, ?array $conversion): void
    {
        if ($conversion === null) {
            return;
        }
        $json = json_encode($conversion, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        if ($json === false || strlen($json) > 262_144) {
            return;
        }
        Database::run(
            'INSERT IGNORE INTO device_attributions (ref, payload, payload_hash, created_at)
             VALUES (:ref, :payload, :hash, :now)',
            ['ref' => $ref, 'payload' => $json, 'hash' => hash('sha256', $json), 'now' => ResourceRepository::now()]
        );
    }

    // --------------------------------------------------------------- forward

    /**
     * @param array<string,string|null> $device
     * @param array<string,mixed>|null  $conversion
     * @return array{hasOffer:bool,url:string,account:?string}
     */
    private function forward(array $device, ?array $conversion, string $sourceIp): array
    {
        $url = Config::string('ATTR_FORWARD_URL', '');
        if ($url === '') {
            return ['hasOffer' => false, 'url' => '', 'account' => null];
        }

        // Fixed outbound vocabulary the external service expects.
        $outbound = [
            'af_id'               => $device['ref'],
            'os'                  => $device['os'],
            'bundle_id'           => $device['bundle_id'],
            'firebase_project_id' => $device['firebase_project_id'],
            'store_id'            => $device['store_id'],
            'push_token'          => $device['push_token'],
            'locale'              => $device['locale'],
            'idfa'                => $device['idfa'],
            'conversion'          => $conversion,
            'source_ip'           => $sourceIp,
        ];

        $result = OutboundHttp::postJson($url, $outbound, Config::int('ATTR_FORWARD_TIMEOUT', 8));
        $decoded = json_decode($result['body'], true);
        $decoded = is_array($decoded) ? $decoded : [];

        $ok = ($decoded['ok'] ?? false) === true;
        $offerUrl = is_string($decoded['url'] ?? null) ? trim((string) $decoded['url']) : '';
        $account = is_string($decoded['account'] ?? null) ? (string) $decoded['account'] : null;
        $hasOffer = $ok && $offerUrl !== '' && filter_var($offerUrl, FILTER_VALIDATE_URL) !== false;

        Database::run(
            'INSERT INTO device_forwards
                (ref, endpoint, request_body, response_code, response_body, ok, offer_url, created_at)
             VALUES (:ref, :endpoint, :req, :code, :resp, :ok, :offer, :now)',
            [
                'ref'      => $device['ref'],
                'endpoint' => mb_substr($url, 0, 500),
                'req'      => json_encode($outbound, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'code'     => $result['code'] > 0 ? $result['code'] : null,
                'resp'     => mb_substr($result['body'], 0, 16_000),
                'ok'       => $hasOffer ? 1 : 0,
                'offer'    => $hasOffer ? mb_substr($offerUrl, 0, 1000) : null,
                'now'      => ResourceRepository::now(),
            ]
        );

        return ['hasOffer' => $hasOffer, 'url' => $offerUrl, 'account' => $account];
    }

    // ----------------------------------------------------------- extraction

    /**
     * @param array<string,mixed> $conversion
     * @return array{status:?string,media_source:?string,campaign:?string}
     */
    private function summarize(array $conversion): array
    {
        return [
            'status'       => $this->cleanString($conversion['af_status'] ?? null, 80),
            'media_source' => $this->cleanString($conversion['media_source'] ?? null, 191),
            'campaign'     => $this->cleanString($conversion['campaign'] ?? null, 191),
        ];
    }

    private function cleanRef(mixed $raw): ?string
    {
        if (!is_string($raw)) {
            return null;
        }
        $value = trim($raw);
        if ($value === '' || mb_strlen($value) > 191 || preg_match('/^[A-Za-z0-9._:\-]{1,191}$/', $value) !== 1) {
            return null;
        }
        return $value;
    }

    private function cleanString(mixed $raw, int $max): ?string
    {
        if (!is_string($raw)) {
            return null;
        }
        $value = trim(preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $raw) ?? '');
        if ($value === '') {
            return null;
        }
        return mb_substr($value, 0, $max);
    }
}
