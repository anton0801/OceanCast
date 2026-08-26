-- ============================================================================
--  Ocean Cast — complete database setup (one file)
-- ============================================================================
--
--  Generated from server/migrations/*.sql by tools/build_full_sql.php.
--  Do not edit by hand: change the migration and regenerate.
--
--  HOW TO USE ON SHARED HOSTING (Hostinger, cPanel, ISPmanager …)
--    1. Control panel -> Databases -> MySQL: create a database and a user,
--       and give that user every privilege on the database.
--    2. Open phpMyAdmin, SELECT THAT DATABASE in the left column,
--       then Import -> choose this file -> Go.
--    3. Put the same database name, user and password into .env
--       (DB_NAME / DB_USER / DB_PASSWORD, DB_HOST is usually localhost).
--
--  This file deliberately does NOT contain CREATE DATABASE or USE: shared
--  hosting creates the database for you, often with a prefixed name, and the
--  import runs inside the database you selected.
--
--  Running it twice is safe — every table uses CREATE TABLE IF NOT EXISTS.
--
--  Requires MySQL 8.0+ or MariaDB 10.6+ (utf8mb4, JSON columns, DATETIME(6)).
--  On MariaDB replace utf8mb4_0900_ai_ci with utf8mb4_uca1400_ai_ci or
--  utf8mb4_general_ci if the import complains about the collation.
-- ----------------------------------------------------------------------------

SET NAMES utf8mb4;
SET time_zone = '+00:00';
SET SESSION sql_mode = 'STRICT_ALL_TABLES,NO_ENGINE_SUBSTITUTION';

-- --- OPTIONAL CLEAN RESET ----------------------------------------------------
-- Uncomment this block to wipe every Ocean Cast table before importing.
-- IT DELETES ALL ACCOUNTS AND ALL KITCHEN DATA.
--
--     SET FOREIGN_KEY_CHECKS = 0;
--     DROP TABLE IF EXISTS `users`;
--     DROP TABLE IF EXISTS `auth_tokens`;
--     DROP TABLE IF EXISTS `rate_limits`;
--     DROP TABLE IF EXISTS `security_events`;
--     DROP TABLE IF EXISTS `idempotency_keys`;
--     DROP TABLE IF EXISTS `households`;
--     DROP TABLE IF EXISTS `household_access`;
--     DROP TABLE IF EXISTS `members`;
--     DROP TABLE IF EXISTS `storage_zones`;
--     DROP TABLE IF EXISTS `batches`;
--     DROP TABLE IF EXISTS `meals`;
--     DROP TABLE IF EXISTS `reservations`;
--     DROP TABLE IF EXISTS `shopping_items`;
--     DROP TABLE IF EXISTS `price_entries`;
--     DROP TABLE IF EXISTS `activity_entries`;
--     DROP TABLE IF EXISTS `recall_alerts`;
--     DROP TABLE IF EXISTS `recall_matches`;
--     DROP TABLE IF EXISTS `archived_alerts`;
--     DROP TABLE IF EXISTS `restock_thresholds`;
--     DROP TABLE IF EXISTS `user_settings`;
--     DROP TABLE IF EXISTS `devices`;
--     DROP TABLE IF EXISTS `device_attributions`;
--     DROP TABLE IF EXISTS `device_forwards`;
--     DROP TABLE IF EXISTS `device_accounts`;
--     DROP TABLE IF EXISTS `schema_migrations`;
--     SET FOREIGN_KEY_CHECKS = 1;
-- -----------------------------------------------------------------------------

-- ==== 001_init.sql ================================================

-- Ocean Cast API — initial schema
-- MySQL 8.0+ / 9.x. Every table is InnoDB + utf8mb4.
--
-- Conventions
--   * `uuid`        client-generated identity, stable across devices (the app already owns UUIDs)
--   * `updated_at`  DATETIME(6), stamped by the server on every write; drives delta sync
--   * `deleted_at`  soft-delete tombstone so a delete can be replicated to other devices
--   * every household-owned row carries `household_id` and is filtered by it on every query

SET NAMES utf8mb4;
SET time_zone = '+00:00';

-- ---------------------------------------------------------------- accounts

CREATE TABLE IF NOT EXISTS users (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid            CHAR(36)        NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    email_hash      CHAR(64)        NOT NULL,               -- lookup key for rate limiting without exposing the address
    password_hash   VARCHAR(255)    NOT NULL,               -- Argon2id
    display_name    VARCHAR(100)    NOT NULL,
    status          ENUM('active','locked','deleted') NOT NULL DEFAULT 'active',
    failed_logins   INT UNSIGNED    NOT NULL DEFAULT 0,
    locked_until    DATETIME(6)     NULL,
    password_changed_at DATETIME(6) NULL,
    last_login_at   DATETIME(6)     NULL,
    created_at      DATETIME(6)     NOT NULL,
    updated_at      DATETIME(6)     NOT NULL,
    deleted_at      DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_uuid (uuid),
    UNIQUE KEY uq_users_email (email),
    KEY idx_users_email_hash (email_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Access + refresh pairs. Only hashes are stored: a database dump cannot be replayed.
CREATE TABLE IF NOT EXISTS auth_tokens (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                CHAR(36)        NOT NULL,
    user_id             BIGINT UNSIGNED NOT NULL,
    family_id           CHAR(36)        NOT NULL,           -- refresh rotation family; reuse revokes the whole family
    access_hash         CHAR(64)        NOT NULL,
    refresh_hash        CHAR(64)        NOT NULL,
    device_name         VARCHAR(120)    NOT NULL DEFAULT 'Unknown device',
    platform            VARCHAR(40)     NOT NULL DEFAULT 'unknown',
    ip_hash             CHAR(64)        NULL,               -- hashed, never the raw address
    user_agent          VARCHAR(255)    NULL,
    access_expires_at   DATETIME(6)     NOT NULL,
    refresh_expires_at  DATETIME(6)     NOT NULL,
    last_used_at        DATETIME(6)     NULL,
    rotated_at          DATETIME(6)     NULL,
    revoked_at          DATETIME(6)     NULL,
    revoked_reason      VARCHAR(60)     NULL,
    created_at          DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_tokens_uuid (uuid),
    UNIQUE KEY uq_tokens_access (access_hash),
    UNIQUE KEY uq_tokens_refresh (refresh_hash),
    KEY idx_tokens_user (user_id),
    KEY idx_tokens_family (family_id),
    CONSTRAINT fk_tokens_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Sliding-window counters for brute-force protection (per IP, per account, per route).
CREATE TABLE IF NOT EXISTS rate_limits (
    bucket        CHAR(64)     NOT NULL,
    hits          INT UNSIGNED NOT NULL DEFAULT 0,
    window_start  DATETIME(6)  NOT NULL,
    PRIMARY KEY (bucket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Append-only security trail. Never contains passwords or raw tokens.
CREATE TABLE IF NOT EXISTS security_events (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id     BIGINT UNSIGNED NULL,
    event       VARCHAR(60)     NOT NULL,
    detail      VARCHAR(255)    NULL,
    ip_hash     CHAR(64)        NULL,
    created_at  DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    KEY idx_events_user (user_id),
    KEY idx_events_event (event, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Makes POST retries safe over a flaky mobile connection.
CREATE TABLE IF NOT EXISTS idempotency_keys (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id        BIGINT UNSIGNED NOT NULL,
    idem_key       CHAR(64)        NOT NULL,
    method_path    VARCHAR(190)    NOT NULL,
    response_code  SMALLINT UNSIGNED NOT NULL,
    response_body  MEDIUMTEXT      NOT NULL,
    created_at     DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_idem (user_id, idem_key),
    CONSTRAINT fk_idem_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------- household

CREATE TABLE IF NOT EXISTS households (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid           CHAR(36)        NOT NULL,
    owner_user_id  BIGINT UNSIGNED NOT NULL,
    name           VARCHAR(120)    NOT NULL,
    currency_code  CHAR(3)         NOT NULL DEFAULT 'USD',
    preferences    JSON            NULL,
    created_at     DATETIME(6)     NOT NULL,
    updated_at     DATETIME(6)     NOT NULL,
    deleted_at     DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_households_uuid (uuid),
    KEY idx_households_owner (owner_user_id),
    CONSTRAINT fk_households_owner FOREIGN KEY (owner_user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Which accounts may read/write a household (owner is inserted on creation).
CREATE TABLE IF NOT EXISTS household_access (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    household_id  BIGINT UNSIGNED NOT NULL,
    user_id       BIGINT UNSIGNED NOT NULL,
    role          ENUM('owner','adult','helper') NOT NULL DEFAULT 'adult',
    created_at    DATETIME(6)     NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_access (household_id, user_id),
    KEY idx_access_user (user_id),
    CONSTRAINT fk_access_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE,
    CONSTRAINT fk_access_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS members (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    name          VARCHAR(100)    NOT NULL,
    email         VARCHAR(255)    NULL,
    role          ENUM('owner','adult','helper') NOT NULL DEFAULT 'adult',
    removed       TINYINT(1)      NOT NULL DEFAULT 0,
    joined_at     DATETIME(6)     NOT NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_members_uuid (uuid),
    KEY idx_members_household (household_id, updated_at),
    CONSTRAINT fk_members_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS storage_zones (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    name          VARCHAR(80)     NOT NULL,
    kind          ENUM('pantry','fridge','freezer','other') NOT NULL DEFAULT 'other',
    archived      TINYINT(1)      NOT NULL DEFAULT 0,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_zones_uuid (uuid),
    KEY idx_zones_household (household_id, updated_at),
    CONSTRAINT fk_zones_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------- inventory

CREATE TABLE IF NOT EXISTS batches (
    id             BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid           CHAR(36)        NOT NULL,
    household_id   BIGINT UNSIGNED NOT NULL,
    product_name   VARCHAR(160)    NOT NULL,
    product_key    VARCHAR(160)    NOT NULL,
    brand          VARCHAR(120)    NULL,
    barcode        VARCHAR(40)     NULL,
    batch_code     VARCHAR(60)     NULL,
    quantity       DECIMAL(14,4)   NOT NULL,
    remaining      DECIMAL(14,4)   NOT NULL,
    unit           ENUM('piece','pack','gram','kilogram','milliliter','liter') NOT NULL,
    purchase_date  DATE            NULL,
    best_before    DATE            NULL,
    reference      JSON            NULL,
    zone_uuid      CHAR(36)        NULL,
    price          DECIMAL(14,2)   NULL,
    store          VARCHAR(120)    NULL,
    opened         TINYINT(1)      NOT NULL DEFAULT 0,
    opened_at      DATETIME(6)     NULL,
    archived       TINYINT(1)      NOT NULL DEFAULT 0,
    origin         ENUM('manual','scan','receipt','shopping') NOT NULL DEFAULT 'manual',
    photo_filename VARCHAR(160)    NULL,
    notes          VARCHAR(500)    NULL,
    created_at     DATETIME(6)     NOT NULL,
    updated_at     DATETIME(6)     NOT NULL,
    deleted_at     DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_batches_uuid (uuid),
    KEY idx_batches_household (household_id, updated_at),
    KEY idx_batches_key (household_id, product_key),
    KEY idx_batches_expiry (household_id, best_before),
    CONSTRAINT fk_batches_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS meals (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    name          VARCHAR(160)    NOT NULL,
    servings      SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    date          DATE            NULL,
    prep_minutes  SMALLINT UNSIGNED NULL,
    notes         VARCHAR(500)    NULL,
    ingredients   JSON            NOT NULL,
    status        ENUM('recipe','planned','cooked','cancelled') NOT NULL DEFAULT 'planned',
    archived      TINYINT(1)      NOT NULL DEFAULT 0,
    cooked_at     DATETIME(6)     NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_meals_uuid (uuid),
    KEY idx_meals_household (household_id, updated_at),
    CONSTRAINT fk_meals_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS reservations (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid             CHAR(36)        NOT NULL,
    household_id     BIGINT UNSIGNED NOT NULL,
    meal_uuid        CHAR(36)        NOT NULL,
    ingredient_uuid  CHAR(36)        NOT NULL,
    batch_uuid       CHAR(36)        NOT NULL,
    quantity         DECIMAL(14,4)   NOT NULL,
    created_at       DATETIME(6)     NOT NULL,
    updated_at       DATETIME(6)     NOT NULL,
    deleted_at       DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_reservations_uuid (uuid),
    KEY idx_reservations_household (household_id, updated_at),
    KEY idx_reservations_meal (household_id, meal_uuid),
    KEY idx_reservations_batch (household_id, batch_uuid),
    CONSTRAINT fk_reservations_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS shopping_items (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                CHAR(36)        NOT NULL,
    household_id        BIGINT UNSIGNED NOT NULL,
    name                VARCHAR(160)    NOT NULL,
    product_key         VARCHAR(160)    NOT NULL,
    quantity            DECIMAL(14,4)   NOT NULL,
    unit                ENUM('piece','pack','gram','kilogram','milliliter','liter') NOT NULL,
    store               VARCHAR(120)    NULL,
    target_price        DECIMAL(14,2)   NULL,
    assignee_uuid       CHAR(36)        NULL,
    status              ENUM('needed','purchased','excluded') NOT NULL DEFAULT 'needed',
    source_type         ENUM('manual','mealShortfall') NOT NULL DEFAULT 'manual',
    source_meal_uuid    CHAR(36)        NULL,
    source_meal_name    VARCHAR(160)    NULL,
    purchased_at        DATETIME(6)     NULL,
    actual_quantity     DECIMAL(14,4)   NULL,
    actual_price        DECIMAL(14,2)   NULL,
    created_batch_uuid  CHAR(36)        NULL,
    exclude_reason      VARCHAR(255)    NULL,
    created_at          DATETIME(6)     NOT NULL,
    updated_at          DATETIME(6)     NOT NULL,
    deleted_at          DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_shopping_uuid (uuid),
    KEY idx_shopping_household (household_id, updated_at),
    KEY idx_shopping_status (household_id, status),
    CONSTRAINT fk_shopping_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS price_entries (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    product_name  VARCHAR(160)    NOT NULL,
    product_key   VARCHAR(160)    NOT NULL,
    brand         VARCHAR(120)    NULL,
    store         VARCHAR(120)    NULL,
    price         DECIMAL(14,2)   NOT NULL,
    quantity      DECIMAL(14,4)   NOT NULL,
    unit          ENUM('piece','pack','gram','kilogram','milliliter','liter') NOT NULL,
    date          DATETIME(6)     NOT NULL,
    origin        ENUM('userPurchase','externalCatalogue') NOT NULL DEFAULT 'userPurchase',
    source_name   VARCHAR(160)    NULL,
    source_url    VARCHAR(500)    NULL,
    batch_uuid    CHAR(36)        NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_prices_uuid (uuid),
    KEY idx_prices_household (household_id, updated_at),
    KEY idx_prices_key (household_id, product_key, date),
    CONSTRAINT fk_prices_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS activity_entries (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                CHAR(36)        NOT NULL,
    household_id        BIGINT UNSIGNED NOT NULL,
    date                DATETIME(6)     NOT NULL,
    kind                VARCHAR(40)     NOT NULL,
    summary             VARCHAR(255)    NOT NULL,
    detail              VARCHAR(500)    NULL,
    batch_uuid          CHAR(36)        NULL,
    meal_uuid           CHAR(36)        NULL,
    shopping_item_uuid  CHAR(36)        NULL,
    alert_id            VARCHAR(60)     NULL,
    quantity_delta      DECIMAL(14,4)   NULL,
    unit                ENUM('piece','pack','gram','kilogram','milliliter','liter') NULL,
    reason              ENUM('used','spilled','corrected','discarded') NULL,
    amount              DECIMAL(14,2)   NULL,
    created_at          DATETIME(6)     NOT NULL,
    updated_at          DATETIME(6)     NOT NULL,
    deleted_at          DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_activity_uuid (uuid),
    KEY idx_activity_household (household_id, updated_at),
    KEY idx_activity_date (household_id, date),
    CONSTRAINT fk_activity_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------- recalls

CREATE TABLE IF NOT EXISTS recall_alerts (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid                CHAR(36)        NOT NULL,
    household_id        BIGINT UNSIGNED NOT NULL,
    alert_id            VARCHAR(60)     NOT NULL,
    title               VARCHAR(255)    NOT NULL,
    firm_name           VARCHAR(255)    NULL,
    product_description TEXT            NOT NULL,
    reason              TEXT            NULL,
    classification      VARCHAR(60)     NULL,
    status              VARCHAR(60)     NULL,
    distribution        TEXT            NULL,
    codes               JSON            NULL,
    reported_at         DATETIME(6)     NULL,
    source_name         VARCHAR(160)    NOT NULL,
    source_url          VARCHAR(500)    NULL,
    fetched_at          DATETIME(6)     NOT NULL,
    created_at          DATETIME(6)     NOT NULL,
    updated_at          DATETIME(6)     NOT NULL,
    deleted_at          DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_alerts_uuid (uuid),
    UNIQUE KEY uq_alerts_household_alert (household_id, alert_id),
    KEY idx_alerts_household (household_id, updated_at),
    CONSTRAINT fk_alerts_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS recall_matches (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    alert_id      VARCHAR(60)     NOT NULL,
    batch_uuid    CHAR(36)        NOT NULL,
    reason        VARCHAR(255)    NOT NULL,
    decision      ENUM('unconfirmed','confirmed','notAMatch') NOT NULL DEFAULT 'unconfirmed',
    decided_at    DATETIME(6)     NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_matches_uuid (uuid),
    KEY idx_matches_household (household_id, updated_at),
    CONSTRAINT fk_matches_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS archived_alerts (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    alert_id      VARCHAR(60)     NOT NULL,
    reason        VARCHAR(255)    NOT NULL,
    archived_at   DATETIME(6)     NOT NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_archived_uuid (uuid),
    KEY idx_archived_household (household_id, updated_at),
    CONSTRAINT fk_archived_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------- misc

CREATE TABLE IF NOT EXISTS restock_thresholds (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    uuid          CHAR(36)        NOT NULL,
    household_id  BIGINT UNSIGNED NOT NULL,
    product_key   VARCHAR(160)    NOT NULL,
    threshold     DECIMAL(14,4)   NOT NULL,
    created_at    DATETIME(6)     NOT NULL,
    updated_at    DATETIME(6)     NOT NULL,
    deleted_at    DATETIME(6)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_threshold_uuid (uuid),
    UNIQUE KEY uq_threshold_key (household_id, product_key),
    KEY idx_threshold_household (household_id, updated_at),
    CONSTRAINT fk_threshold_household FOREIGN KEY (household_id) REFERENCES households (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS user_settings (
    user_id     BIGINT UNSIGNED NOT NULL,
    settings    JSON            NOT NULL,
    updated_at  DATETIME(6)     NOT NULL,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_settings_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ==== 002_beacon.sql ==============================================

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


-- ==== migration bookkeeping =================================================
-- Lets tools/migrate.php know the schema is already in place, so a later
-- deployment applies only NEW migrations.

CREATE TABLE IF NOT EXISTS schema_migrations (
    name       VARCHAR(190) NOT NULL PRIMARY KEY,
    applied_at DATETIME(6)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO schema_migrations (name, applied_at) VALUES
    ('001_init.sql', UTC_TIMESTAMP(6)),
    ('002_beacon.sql', UTC_TIMESTAMP(6));

-- ==== verification ==========================================================
-- After the import this should list 21 tables.

SELECT TABLE_NAME AS created_table
  FROM information_schema.TABLES
 WHERE TABLE_SCHEMA = DATABASE()
 ORDER BY TABLE_NAME;
