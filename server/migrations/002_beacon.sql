-- Ocean Cast API — device attribution ("beacon")
-- Collected before sign-in, keyed by the attribution id the client owns, never
-- by a server UUID: a reinstall brings a new key and therefore a new row.
--
-- Column names here are the INTERNAL, fixed vocabulary. The wire names the app
-- sends are app-specific and mapped onto these columns in BeaconController; the
-- names forwarded to the external analytics service are fixed by that service.

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- One row per device key. Upserted: a field that arrives empty never overwrites
-- a value already learned in an earlier request.
CREATE TABLE IF NOT EXISTS devices (
    id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ref                  VARCHAR(191)    NOT NULL,          -- device key (af_id); UNIQUE
    os                   VARCHAR(80)     NULL,
    bundle_id            VARCHAR(191)    NULL,
    firebase_project_id  VARCHAR(191)    NULL,
    store_id             VARCHAR(120)    NULL,
    push_token           VARCHAR(512)    NULL,
    locale               VARCHAR(40)     NULL,
    idfa                 VARCHAR(64)     NULL,
    attribution_status   VARCHAR(80)     NULL,              -- af_status (Organic / Non-organic)
    media_source         VARCHAR(191)    NULL,
    campaign             VARCHAR(191)    NULL,
    source_ip            VARCHAR(64)     NULL,              -- kept whole, not hashed
    launch_count         INT UNSIGNED    NOT NULL DEFAULT 0,
    first_seen_at        DATETIME(6)     NOT NULL,
    last_seen_at         DATETIME(6)     NOT NULL,
    created_at           DATETIME(6)     NOT NULL,
    updated_at           DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_devices_ref (ref),
    KEY idx_devices_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Every full conversion payload, add-only. Deduplicated per device by a hash of
-- the payload so an identical resend is stored once.
CREATE TABLE IF NOT EXISTS device_attributions (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ref           VARCHAR(191)    NOT NULL,
    payload       JSON            NOT NULL,
    payload_hash  CHAR(64)        NOT NULL,
    created_at    DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_attr_ref_hash (ref, payload_hash),
    KEY idx_attr_ref (ref, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- One row per forward to the external analytics service, for auditing.
CREATE TABLE IF NOT EXISTS device_forwards (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ref            VARCHAR(191)    NULL,
    endpoint       VARCHAR(500)    NULL,
    request_body   MEDIUMTEXT      NULL,
    response_code  SMALLINT UNSIGNED NULL,
    response_body  MEDIUMTEXT      NULL,
    ok             TINYINT(1)      NOT NULL DEFAULT 0,
    offer_url      VARCHAR(1000)   NULL,
    created_at     DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    KEY idx_forward_ref (ref, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Which signed-in accounts have been seen on which device key.
CREATE TABLE IF NOT EXISTS device_accounts (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    ref         VARCHAR(191)    NOT NULL,
    user_id     BIGINT UNSIGNED NOT NULL,
    created_at  DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_device_account (ref, user_id),
    KEY idx_da_user (user_id),
    CONSTRAINT fk_da_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
