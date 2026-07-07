-- ============================================================
-- SESSION SETTING: suppress informational NOTICEs (e.g. "table does
-- not exist, skipping" / "extension already exists, skipping") so
-- pgAdmin's Messages tab only shows real WARNINGs/ERRORs and the
-- final "Query returned successfully" status.
-- ============================================================
SET client_min_messages TO WARNING;


-- ============================================================
-- DROP ALL TABLES FIRST (reverse of creation order, respects FK deps)
-- Safe to re-run: IF EXISTS prevents errors if tables don't exist yet
-- CASCADE removes dependent constraints/views automatically
-- ============================================================
DROP TABLE IF EXISTS profile_preferred_genres CASCADE;
DROP TABLE IF EXISTS profile_preferences CASCADE;
DROP TABLE IF EXISTS search_history CASCADE;
DROP TABLE IF EXISTS downloads CASCADE;
DROP TABLE IF EXISTS my_list CASCADE;
DROP TABLE IF EXISTS watch_history CASCADE;
DROP TABLE IF EXISTS ratings CASCADE;
DROP TABLE IF EXISTS user_devices CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS subscriptions CASCADE;
DROP TABLE IF EXISTS plan_allowed_devices CASCADE;
DROP TABLE IF EXISTS subscription_plans CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS content_availability CASCADE;
DROP TABLE IF EXISTS content_cast CASCADE;
DROP TABLE IF EXISTS content_languages CASCADE;
DROP TABLE IF EXISTS content_genres CASCADE;
DROP TABLE IF EXISTS episodes CASCADE;
DROP TABLE IF EXISTS content_parts CASCADE;
DROP TABLE IF EXISTS seasons CASCADE;
DROP TABLE IF EXISTS content CASCADE;
DROP TABLE IF EXISTS actors CASCADE;
DROP TABLE IF EXISTS languages CASCADE;
DROP TABLE IF EXISTS genres CASCADE;
DROP TABLE IF EXISTS content_rating_levels CASCADE;  -- removed in this version, dropped if left over from v3


-- ============================================================
-- PROJECT  : Netflix-Type Streaming Platform
-- DATABASE : PostgreSQL
-- VERSION  : 5.0 — Final Production-Ready DDL (Resume Edition)
-- TABLES   : 25
-- MODULES  : Content & Catalog · Users & Accounts · Engagement
-- NOTES    : All PK / FK / UQ / CHK constraints verified.
--            Partial unique indexes follow each relevant table.
--            Run this script top-to-bottom in one transaction.
--
-- CHANGES FROM v3:
--   • REMOVED content_rating_levels table entirely (no more
--     age-certification / age-rating-limit system in this version).
--   • REMOVED content.age_certification column and its FK.
--   • ADDED content.content_category column (free-form catalogue
--     tag, e.g. 'Netflix Original', 'Trending Now', 'Documentary').
--   • REMOVED profiles.age_rating_limit, pin_hash, language,
--     autoplay_next, autoplay_previews (autoplay + language moved
--     to profile_preferences below).
--   • REMOVED users.preferred_lang, last_login_at, deleted_at.
--   • ADDED plan_allowed_devices — new M:M lookup table mapping
--     each subscription plan to the device types it supports.
--   • REMOVED subscriptions.trial_end_date, promo_code, discount_pct.
--   • ADDED payments.upi_id and payments.upi_app columns, plus
--     chk_payment_method_fields enforcing that card fields
--     (card_last4/card_brand) and UPI fields (upi_id/upi_app)
--     are mutually exclusive on a single payment row.
--   • SIMPLIFIED user_devices down to device_id, user_id, os_type,
--     device_type, last_active_at (dropped fingerprinting/session
--     tracking columns not needed for this scope).
--   • RENAMED ratings.rating_value -> ratings.is_liked (BOOLEAN),
--     switching from a 1-5 star scale to a simple like/dislike.
--   • ADDED profile_preferences.language, autoplay_next,
--     autoplay_previews (moved in from profiles); REMOVED
--     profile_preferences.data_saver_mode.
--
-- CHANGES FROM v4:
--   • ADDED content_parts — new table for movies released in parts
--     (e.g. 'Part 1', 'Part 2'), mirroring how episodes work for series.
--   • EXTENDED ratings with season_id, episode_id, and part_id (all
--     nullable) so a profile can rate at four levels: a whole movie
--     or series (content_id only), one season, one episode, or one
--     part of a multi-part movie. is_liked stays a simple TRUE/FALSE.
--   • REPLACED the single uq_ratings_profile_content constraint with
--     four partial unique indexes (one per rating level), since a
--     plain UNIQUE constraint would let NULL columns bypass duplicate
--     detection on whole-title ratings — the same pattern already
--     used for content_languages defaults and active downloads.
-- ============================================================

BEGIN;

-- ============================================================
-- CREATION ORDER (respects all FK dependencies)
-- ============================================================
--  1.  genres                   (no deps — pure lookup)
--  2.  languages                (no deps — pure lookup)
--  3.  actors                   (no deps — pure lookup)
--  4.  content                  (no deps)
--  5.  seasons                  (deps: content)
--  6.  episodes                 (deps: seasons)
--  7.  content_parts             (deps: content)
--  8.  content_genres           (deps: content, genres)
--  9.  content_languages        (deps: content, languages)
-- 10.  content_cast             (deps: content, actors)
-- 11.  content_availability     (deps: content)
-- 12.  users                    (no deps)
-- 13.  profiles                 (deps: users)
-- 14.  subscription_plans       (no deps)
-- 15.  plan_allowed_devices     (deps: subscription_plans)
-- 16.  subscriptions            (deps: users, subscription_plans)
-- 17.  payments                 (deps: subscriptions, users)
-- 18.  user_devices             (deps: users)
-- 19.  ratings                  (deps: profiles, content, seasons, episodes, content_parts)
-- 20.  watch_history            (deps: profiles, content, episodes)
-- 21.  my_list                  (deps: profiles, content)
-- 22.  downloads                (deps: profiles, content, episodes, user_devices)
-- 23.  search_history           (deps: profiles, user_devices)
-- 24.  profile_preferences      (deps: profiles)
-- 25.  profile_preferred_genres (deps: profiles, genres)
-- ============================================================


-- ============================================================
-- TABLE 1: genres
-- Lookup table of genre categories for content tagging.
-- ============================================================
CREATE TABLE genres (
    genre_id    BIGSERIAL       NOT NULL,
    genre_name  VARCHAR(100)    NOT NULL,
    description TEXT            NULL,

    CONSTRAINT pk_genres
        PRIMARY KEY (genre_id),

    CONSTRAINT uq_genre_name
        UNIQUE (genre_name)
);


-- ============================================================
-- TABLE 2: languages
-- Lookup table of supported languages for audio and subtitles.
-- ============================================================
CREATE TABLE languages (
    language_id     BIGSERIAL       NOT NULL,
    language_name   VARCHAR(100)    NOT NULL,
    language_code   VARCHAR(10)     NOT NULL,

    CONSTRAINT pk_languages
        PRIMARY KEY (language_id),

    CONSTRAINT uq_language_name
        UNIQUE (language_name),

    CONSTRAINT uq_language_code
        UNIQUE (language_code)
);


-- ============================================================
-- TABLE 3: actors
-- Master record for all cast members and talent.
-- ============================================================
CREATE TABLE actors (
    actor_id        BIGSERIAL       NOT NULL,
    actor_name      VARCHAR(255)    NOT NULL,
    date_of_birth   DATE            NULL,
    gender          VARCHAR(20)     NULL,
    nationality     VARCHAR(100)    NULL,
    bio             TEXT            NULL,
    photo_url       TEXT            NULL,

    CONSTRAINT pk_actors
        PRIMARY KEY (actor_id)
);


-- ============================================================
-- TABLE 4: content
-- Master catalogue entry for every Movie or Series title.
-- duration_minutes is NULL for Series; Episodes carry runtime.
-- content_category is a free-form catalogue tag (e.g. 'Netflix
-- Original', 'Trending Now', 'Documentary') used for row/shelf
-- grouping on the home screen — independent of genre tagging.
-- ============================================================
CREATE TABLE content (
    content_id          BIGSERIAL       NOT NULL,
    title               VARCHAR(255)    NOT NULL,
    description         TEXT            NULL,
    content_type        VARCHAR(20)     NOT NULL,
    content_category     VARCHAR(50)     NULL,
    release_date        DATE            NULL,
    duration_minutes    INTEGER         NULL,
    poster_url          TEXT            NULL,
    trailer_url         TEXT            NULL,
    status              VARCHAR(20)     NOT NULL    DEFAULT 'Active',
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_content
        PRIMARY KEY (content_id),

    CONSTRAINT chk_content_type
        CHECK (content_type IN ('Movie', 'Series')),

    CONSTRAINT chk_content_status
        CHECK (status IN ('Active', 'Inactive', 'ComingSoon')),

    -- duration_minutes must be positive when supplied
    CONSTRAINT chk_duration_positive
        CHECK (duration_minutes > 0),

    -- Series rows must have NULL duration (runtime lives on episodes)
    CONSTRAINT chk_duration_series_null
        CHECK (
            (content_type = 'Series' AND duration_minutes IS NULL)
            OR
            (content_type = 'Movie')
        )
);


-- ============================================================
-- TABLE 5: seasons
-- Represents individual seasons of a Series title.
-- ============================================================
CREATE TABLE seasons (
    season_id       BIGSERIAL       NOT NULL,
    content_id      BIGINT          NOT NULL,
    season_number   INTEGER         NOT NULL,
    title           VARCHAR(255)    NULL,
    description     TEXT            NULL,
    release_date    DATE            NULL,
    created_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_seasons
        PRIMARY KEY (season_id),

    CONSTRAINT fk_seasons_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- Prevent two "Season 1" rows for the same show
    CONSTRAINT uq_seasons_content_season
        UNIQUE (content_id, season_number),

    CONSTRAINT chk_season_number_positive
        CHECK (season_number > 0)
);


-- ============================================================
-- TABLE 6: episodes
-- Represents individual episodes within a season.
-- ============================================================
CREATE TABLE episodes (
    episode_id          BIGSERIAL       NOT NULL,
    season_id           BIGINT          NOT NULL,
    episode_number      INTEGER         NOT NULL,
    title               VARCHAR(255)    NOT NULL,
    description         TEXT            NULL,
    duration_minutes    INTEGER         NULL,
    release_date        DATE            NULL,
    video_url           TEXT            NULL,
    thumbnail_url       TEXT            NULL,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_episodes
        PRIMARY KEY (episode_id),

    CONSTRAINT fk_episodes_season
        FOREIGN KEY (season_id)
        REFERENCES seasons (season_id)
        ON DELETE CASCADE,

    -- Prevent duplicate episode numbering within the same season
    CONSTRAINT uq_episodes_season_episode
        UNIQUE (season_id, episode_number),

    CONSTRAINT chk_episode_number_positive
        CHECK (episode_number > 0),

    CONSTRAINT chk_episode_duration_positive
        CHECK (duration_minutes > 0)
);


-- ============================================================
-- TABLE 7: content_parts
-- Represents individual parts of a Movie released in multiple
-- parts (e.g. 'Part 1', 'Part 2') — the Movie-side equivalent of
-- episodes. content.content_type should be 'Movie' for any title
-- that has rows here; enforcing that link is an app-layer check,
-- the same pattern used elsewhere in this schema for cross-table
-- consistency (e.g. episode_id -> content_id in watch_history).
-- ============================================================
CREATE TABLE content_parts (
    part_id             BIGSERIAL       NOT NULL,
    content_id          BIGINT          NOT NULL,
    part_number         INTEGER         NOT NULL,
    title               VARCHAR(255)    NOT NULL,
    description         TEXT            NULL,
    duration_minutes    INTEGER         NULL,
    release_date        DATE            NULL,
    video_url           TEXT            NULL,
    thumbnail_url       TEXT            NULL,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_content_parts
        PRIMARY KEY (part_id),

    CONSTRAINT fk_content_parts_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- Prevent two "Part 1" rows for the same movie
    CONSTRAINT uq_content_parts_content_part
        UNIQUE (content_id, part_number),

    CONSTRAINT chk_content_parts_number_positive
        CHECK (part_number > 0),

    CONSTRAINT chk_content_parts_duration_positive
        CHECK (duration_minutes > 0)
);


-- ============================================================
-- TABLE 8: content_genres
-- Many-to-many: links content titles to their genre tags.
-- ============================================================
CREATE TABLE content_genres (
    content_id  BIGINT  NOT NULL,
    genre_id    BIGINT  NOT NULL,

    CONSTRAINT pk_content_genres
        PRIMARY KEY (content_id, genre_id),

    CONSTRAINT fk_content_genres_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_content_genres_genre
        FOREIGN KEY (genre_id)
        REFERENCES genres (genre_id)
        ON DELETE CASCADE
);


-- ============================================================
-- TABLE 9: content_languages
-- Audio and subtitle track assignments per content title.
-- One default track per type per title is enforced by partial index.
-- ============================================================
CREATE TABLE content_languages (
    content_language_id BIGSERIAL       NOT NULL,
    content_id          BIGINT          NOT NULL,
    language_id         BIGINT          NOT NULL,
    language_type       VARCHAR(20)     NOT NULL,
    is_default          BOOLEAN         NOT NULL    DEFAULT FALSE,

    CONSTRAINT pk_content_languages
        PRIMARY KEY (content_language_id),

    CONSTRAINT fk_content_languages_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_content_languages_language
        FOREIGN KEY (language_id)
        REFERENCES languages (language_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_language_type
        CHECK (language_type IN ('Audio', 'Subtitle', 'Both')),

    -- Prevent duplicate tracks: same content + language + type
    CONSTRAINT uq_content_language_type
        UNIQUE (content_id, language_id, language_type)
);

-- At most one default Audio track and one default Subtitle track per title
CREATE UNIQUE INDEX uix_content_languages_default
    ON content_languages (content_id, language_type)
    WHERE is_default = TRUE;


-- ============================================================
-- TABLE 10: content_cast
-- Links actors to content titles with character details.
-- An actor may play multiple characters in the same title.
-- ============================================================
CREATE TABLE content_cast (
    cast_id         BIGSERIAL       NOT NULL,
    content_id      BIGINT          NOT NULL,
    actor_id        BIGINT          NOT NULL,
    character_name  VARCHAR(255)    NOT NULL,
    cast_order      INTEGER         NULL,
    is_main_cast    BOOLEAN         NOT NULL    DEFAULT FALSE,

    CONSTRAINT pk_content_cast
        PRIMARY KEY (cast_id),

    CONSTRAINT fk_content_cast_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_content_cast_actor
        FOREIGN KEY (actor_id)
        REFERENCES actors (actor_id)
        ON DELETE RESTRICT,

    -- Same actor can play two characters; duplicate (content, actor, character) blocked
    CONSTRAINT uq_content_cast_unique
        UNIQUE (content_id, actor_id, character_name)
);


-- Required for the EXCLUDE USING gist constraint on content_availability.
-- Safe to run even if already installed.
CREATE EXTENSION IF NOT EXISTS btree_gist;


-- ============================================================
-- TABLE 11: content_availability
-- Country-level availability windows for each content title.
-- "Available now" = CURRENT_DATE BETWEEN available_from AND
-- available_to (or available_to IS NULL for indefinite).
-- No redundant is_available boolean — computed from dates only.
-- ============================================================
CREATE TABLE content_availability (
    availability_id BIGSERIAL       NOT NULL,
    content_id      BIGINT          NOT NULL,
    country_code    VARCHAR(10)     NOT NULL,
    available_from  DATE            NOT NULL,
    available_to    DATE            NULL,
    region_notes    TEXT            NULL,

    CONSTRAINT pk_content_availability
        PRIMARY KEY (availability_id),

    CONSTRAINT fk_content_availability_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- available_to must be strictly after available_from when provided
    CONSTRAINT chk_availability_date_order
        CHECK (available_to IS NULL OR available_to > available_from)
);

-- Prevent overlapping availability windows for the same (content, country).
-- Requires btree_gist (created above).
ALTER TABLE content_availability
    ADD CONSTRAINT excl_content_availability_no_overlap
    EXCLUDE USING gist (
        content_id   WITH =,
        country_code WITH =,
        daterange(available_from, COALESCE(available_to, '9999-12-31'), '[)') WITH &&
    );


-- ============================================================
-- TABLE 12: users
-- Core account table — identity, login, and account status only.
-- Billing state belongs in subscriptions, not here.
-- ============================================================
CREATE TABLE users (
    user_id         BIGSERIAL       NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    full_name       VARCHAR(150)    NOT NULL,
    phone_number    VARCHAR(20)     NULL,
    date_of_birth   DATE            NOT NULL,
    country_code    CHAR(2)         NOT NULL,
    account_status  VARCHAR(20)     NOT NULL    DEFAULT 'pending',
    email_verified  BOOLEAN         NOT NULL    DEFAULT FALSE,
    avatar_url      VARCHAR(500)    NULL,
    created_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_users
        PRIMARY KEY (user_id),

    CONSTRAINT uq_users_email
        UNIQUE (email),

    CONSTRAINT uq_users_phone
        UNIQUE (phone_number),

    -- 'cancelled' intentionally excluded — belongs to subscriptions.status
    CONSTRAINT chk_account_status
        CHECK (account_status IN ('active', 'suspended', 'pending'))
);


-- ============================================================
-- TABLE 13: profiles
-- Sub-profiles under one user account.
-- Profile count cap is plan-driven (app-enforced via max_profiles).
-- ============================================================
CREATE TABLE profiles (
    profile_id          BIGSERIAL       NOT NULL,
    user_id             BIGINT          NOT NULL,
    profile_name        VARCHAR(50)     NOT NULL,
    avatar_url          VARCHAR(500)    NULL,
    is_kids             BOOLEAN         NOT NULL    DEFAULT FALSE,
    is_primary          BOOLEAN         NOT NULL    DEFAULT FALSE,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_profiles
        PRIMARY KEY (profile_id),

    CONSTRAINT fk_profiles_user
        FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE CASCADE
);

-- At most ONE primary profile per user account
CREATE UNIQUE INDEX uix_profiles_one_primary_per_user
    ON profiles (user_id)
    WHERE is_primary = TRUE;


-- ============================================================
-- TABLE 14: subscription_plans
-- Master list of subscription tiers and feature entitlements.
-- max_downloads = 0 means downloads not allowed (no separate boolean).
-- ============================================================
CREATE TABLE subscription_plans (
    plan_id         SERIAL          NOT NULL,
    plan_name       VARCHAR(50)     NOT NULL,
    price_monthly   DECIMAL(8,2)    NOT NULL,
    price_yearly    DECIMAL(8,2)    NULL,
    currency        CHAR(3)         NOT NULL    DEFAULT 'USD',
    max_screens     SMALLINT        NOT NULL,
    max_profiles    SMALLINT        NOT NULL,
    video_quality   VARCHAR(20)     NOT NULL,
    hdr_support     BOOLEAN         NOT NULL    DEFAULT FALSE,
    dolby_atmos     BOOLEAN         NOT NULL    DEFAULT FALSE,
    max_downloads   INTEGER         NOT NULL    DEFAULT 0,
    ads_supported   BOOLEAN         NOT NULL    DEFAULT FALSE,
    is_active       BOOLEAN         NOT NULL    DEFAULT TRUE,
    created_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_subscription_plans
        PRIMARY KEY (plan_id),

    CONSTRAINT uq_plan_name
        UNIQUE (plan_name),

    CONSTRAINT chk_video_quality
        CHECK (video_quality IN ('SD', 'HD', 'Full HD', '4K Ultra HD')),

    CONSTRAINT chk_price_monthly_positive
        CHECK (price_monthly > 0),

    CONSTRAINT chk_price_yearly_positive
        CHECK (price_yearly IS NULL OR price_yearly > 0),

    CONSTRAINT chk_max_screens_positive
        CHECK (max_screens >= 1),

    CONSTRAINT chk_max_profiles_positive
        CHECK (max_profiles >= 1),

    CONSTRAINT chk_max_downloads_non_negative
        CHECK (max_downloads >= 0)
);


-- ============================================================
-- TABLE 15: plan_allowed_devices  *** NEW TABLE ***
-- Many-to-many lookup: which device types each subscription plan
-- is permitted to stream on (e.g. Basic = smartphone/tablet only,
-- Premium = all device types).
-- ============================================================
CREATE TABLE plan_allowed_devices (
    plan_id     INTEGER         NOT NULL,
    device_type VARCHAR(20)     NOT NULL,

    CONSTRAINT pk_plan_allowed_devices
        PRIMARY KEY (plan_id, device_type),

    CONSTRAINT fk_plan_allowed_devices_plan
        FOREIGN KEY (plan_id)
        REFERENCES subscription_plans (plan_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_plan_allowed_device_type
        CHECK (device_type IN (
            'smartphone', 'tablet', 'smart_tv',
            'laptop', 'desktop', 'game_console'
        ))
);


-- ============================================================
-- TABLE 16: subscriptions
-- Active and historical subscription records per user.
-- Partial unique index enforces one active subscription per user.
-- next_billing_date is NULL for cancelled/expired rows.
-- ============================================================
CREATE TABLE subscriptions (
    subscription_id     BIGSERIAL       NOT NULL,
    user_id             BIGINT          NOT NULL,
    plan_id             INTEGER         NOT NULL,
    status              VARCHAR(20)     NOT NULL,
    billing_cycle       VARCHAR(10)     NOT NULL,
    start_date          DATE            NOT NULL,
    end_date            DATE            NULL,
    next_billing_date   DATE            NULL,
    auto_renew          BOOLEAN         NOT NULL    DEFAULT TRUE,
    cancelled_at        TIMESTAMP       NULL,
    cancellation_reason VARCHAR(255)    NULL,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_subscriptions
        PRIMARY KEY (subscription_id),

    CONSTRAINT fk_subscriptions_user
        FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_subscriptions_plan
        FOREIGN KEY (plan_id)
        REFERENCES subscription_plans (plan_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_subscription_status
        CHECK (status IN ('active', 'paused', 'cancelled', 'expired')),

    CONSTRAINT chk_billing_cycle
        CHECK (billing_cycle IN ('monthly', 'yearly')),

    -- next_billing_date required when active/paused; MUST be NULL when cancelled/expired
    CONSTRAINT chk_next_billing_date
        CHECK (
            (status IN ('active', 'paused') AND next_billing_date IS NOT NULL)
            OR
            (status IN ('cancelled', 'expired') AND next_billing_date IS NULL)
        ),

    CONSTRAINT chk_subscription_date_order
        CHECK (end_date IS NULL OR end_date > start_date)
);

-- At most one active subscription per user at any time
CREATE UNIQUE INDEX uix_subscriptions_one_active_per_user
    ON subscriptions (user_id)
    WHERE status = 'active';


-- ============================================================
-- TABLE 17: payments
-- All payment transactions and billing records.
-- user_id is intentional denormalization: fast billing queries
-- without joins, audit trail preserved if subscription deleted.
-- upi_id / upi_app populated only when payment_method = 'upi';
-- card_last4 / card_brand populated only for card payments.
-- ============================================================
CREATE TABLE payments (
    payment_id          BIGSERIAL       NOT NULL,
    subscription_id     BIGINT          NOT NULL,
    user_id             BIGINT          NOT NULL,
    amount              DECIMAL(10,2)   NOT NULL,
    currency            CHAR(3)         NOT NULL    DEFAULT 'USD',
    payment_method      VARCHAR(20)     NOT NULL,
    payment_status      VARCHAR(20)     NOT NULL,
    transaction_id      VARCHAR(255)    NULL,
    gateway_name        VARCHAR(50)     NOT NULL,
    gateway_response    JSON            NULL,
    card_last4          CHAR(4)         NULL,
    card_brand          VARCHAR(20)     NULL,
    upi_id               VARCHAR(100)    NULL,
    upi_app               VARCHAR(50)     NULL,
    billing_address     VARCHAR(500)    NULL,
    invoice_url         VARCHAR(500)    NULL,
    refund_amount       DECIMAL(10,2)   NOT NULL    DEFAULT 0.00,
    refunded_at         TIMESTAMP       NULL,
    paid_at             TIMESTAMP       NULL,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_payments
        PRIMARY KEY (payment_id),

    CONSTRAINT fk_payments_subscription
        FOREIGN KEY (subscription_id)
        REFERENCES subscriptions (subscription_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_payments_user
        FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_payments_transaction_id
        UNIQUE (transaction_id),

    CONSTRAINT chk_payment_method
        CHECK (payment_method IN ('credit_card', 'debit_card', 'paypal', 'upi', 'gift_card')),

    CONSTRAINT chk_payment_status
        CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded', 'chargeback')),

    CONSTRAINT chk_payment_amount_positive
        CHECK (amount > 0),

    CONSTRAINT chk_refund_amount_non_negative
        CHECK (refund_amount >= 0),

    -- Refund cannot exceed what was charged
    CONSTRAINT chk_refund_not_exceed_amount
        CHECK (refund_amount <= amount),

    -- Card fields and UPI fields are mutually exclusive — a payment is
    -- either a card transaction or a UPI transaction, never both
    CONSTRAINT chk_payment_method_fields
        CHECK (
            NOT (
                (card_last4 IS NOT NULL OR card_brand IS NOT NULL)
                AND
                (upi_id IS NOT NULL OR upi_app IS NOT NULL)
            )
        )
);


-- ============================================================
-- TABLE 18: user_devices
-- Registered devices per user, simplified to the essentials:
-- what platform, what kind of device, and when last seen.
-- ============================================================
CREATE TABLE user_devices (
    device_id       BIGSERIAL       NOT NULL,
    user_id         BIGINT          NOT NULL,
    os_type         VARCHAR(30)     NULL,
    device_type     VARCHAR(20)     NOT NULL,
    last_active_at  TIMESTAMP       NULL,

    CONSTRAINT pk_user_devices
        PRIMARY KEY (device_id),

    CONSTRAINT fk_user_devices_user
        FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_device_type
        CHECK (device_type IN (
            'smartphone', 'tablet', 'smart_tv',
            'laptop', 'desktop', 'game_console'
        ))
);


-- ============================================================
-- TABLE 19: ratings
-- Simple like/dislike + optional review, at ANY of four levels:
--   • Whole title   — content_id only (season/episode/part all NULL)
--   • One season    — content_id + season_id
--   • One episode   — content_id + season_id + episode_id
--   • One movie part — content_id + part_id
-- A row is either "series-side" (season_id/episode_id) or
-- "movie-side" (part_id), never both. One rating per profile per
-- exact level, enforced below by four partial unique indexes rather
-- than a single UNIQUE constraint, since Postgres UNIQUE treats NULLs
-- as distinct and would silently allow duplicate whole-title ratings.
-- season_id/episode_id -> content_id and part_id -> content_id
-- consistency (e.g. season 5 actually belonging to content 2) is an
-- app-layer check, the same pattern used elsewhere in this schema.
-- ============================================================
CREATE TABLE ratings (
    rating_id       BIGSERIAL   NOT NULL,
    profile_id      BIGINT      NOT NULL,
    content_id      BIGINT      NOT NULL,
    season_id       BIGINT      NULL,
    episode_id      BIGINT      NULL,
    part_id         BIGINT      NULL,
    is_liked        BOOLEAN     NOT NULL,
    review_text     TEXT        NULL,
    created_at      TIMESTAMP   NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP   NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_ratings
        PRIMARY KEY (rating_id),

    CONSTRAINT fk_ratings_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ratings_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ratings_season
        FOREIGN KEY (season_id)
        REFERENCES seasons (season_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ratings_episode
        FOREIGN KEY (episode_id)
        REFERENCES episodes (episode_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ratings_part
        FOREIGN KEY (part_id)
        REFERENCES content_parts (part_id)
        ON DELETE CASCADE,

    -- An episode rating must also specify its season
    CONSTRAINT chk_ratings_episode_needs_season
        CHECK (episode_id IS NULL OR season_id IS NOT NULL),

    -- A row is either series-side (season/episode) or movie-side (part), never both
    CONSTRAINT chk_ratings_part_excludes_season_episode
        CHECK (part_id IS NULL OR (season_id IS NULL AND episode_id IS NULL))
);

-- One rating per profile per whole title (season, episode, part all NULL)
CREATE UNIQUE INDEX uix_ratings_content_level
    ON ratings (profile_id, content_id)
    WHERE season_id IS NULL AND episode_id IS NULL AND part_id IS NULL;

-- One rating per profile per season (episode NULL)
CREATE UNIQUE INDEX uix_ratings_season_level
    ON ratings (profile_id, content_id, season_id)
    WHERE season_id IS NOT NULL AND episode_id IS NULL;

-- One rating per profile per episode
CREATE UNIQUE INDEX uix_ratings_episode_level
    ON ratings (profile_id, content_id, season_id, episode_id)
    WHERE episode_id IS NOT NULL;

-- One rating per profile per movie part
CREATE UNIQUE INDEX uix_ratings_part_level
    ON ratings (profile_id, content_id, part_id)
    WHERE part_id IS NOT NULL;


-- ============================================================
-- TABLE 20: watch_history
-- Append-only log of viewing sessions per profile.
-- Most recent row = current resume point for that title/episode.
-- episode_id → content_id consistency enforced at app layer.
-- ============================================================
CREATE TABLE watch_history (
    watch_id                BIGSERIAL   NOT NULL,
    profile_id              BIGINT      NOT NULL,
    content_id              BIGINT      NOT NULL,
    episode_id              BIGINT      NULL,
    watched_at              TIMESTAMP   NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    watch_duration_seconds  INTEGER     NOT NULL    DEFAULT 0,
    progress_seconds        INTEGER     NOT NULL    DEFAULT 0,
    completed               BOOLEAN     NOT NULL    DEFAULT FALSE,

    CONSTRAINT pk_watch_history
        PRIMARY KEY (watch_id),

    CONSTRAINT fk_watch_history_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_watch_history_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- NULL allowed: Movie rows have no episode
    CONSTRAINT fk_watch_history_episode
        FOREIGN KEY (episode_id)
        REFERENCES episodes (episode_id)
        ON DELETE SET NULL,

    CONSTRAINT chk_watch_duration_non_negative
        CHECK (watch_duration_seconds >= 0),

    CONSTRAINT chk_progress_non_negative
        CHECK (progress_seconds >= 0)
);


-- ============================================================
-- TABLE 21: my_list
-- Profile-level watchlist (saved-for-later titles).
-- Same title cannot appear twice in one profile's list.
-- ============================================================
CREATE TABLE my_list (
    my_list_id  BIGSERIAL   NOT NULL,
    profile_id  BIGINT      NOT NULL,
    content_id  BIGINT      NOT NULL,
    added_at    TIMESTAMP   NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_my_list
        PRIMARY KEY (my_list_id),

    CONSTRAINT fk_my_list_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_my_list_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- Prevent the same title appearing twice in one profile's list
    CONSTRAINT uq_my_list_profile_content
        UNIQUE (profile_id, content_id)
);


-- ============================================================
-- TABLE 22: downloads
-- Offline downloads per profile and device.
-- Partial unique index allows Expired/Deleted history rows
-- while blocking duplicate concurrent Active downloads.
-- ============================================================
CREATE TABLE downloads (
    download_id     BIGSERIAL       NOT NULL,
    profile_id      BIGINT          NOT NULL,
    content_id      BIGINT          NOT NULL,
    episode_id      BIGINT          NULL,
    device_id       BIGINT          NOT NULL,
    downloaded_at   TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    expiry_date     DATE            NULL,
    file_size_mb    DECIMAL(10,2)   NOT NULL,
    download_status VARCHAR(20)     NOT NULL,

    CONSTRAINT pk_downloads
        PRIMARY KEY (download_id),

    CONSTRAINT fk_downloads_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_downloads_content
        FOREIGN KEY (content_id)
        REFERENCES content (content_id)
        ON DELETE CASCADE,

    -- NULL allowed for Movie downloads (no episode)
    CONSTRAINT fk_downloads_episode
        FOREIGN KEY (episode_id)
        REFERENCES episodes (episode_id)
        ON DELETE SET NULL,

    CONSTRAINT fk_downloads_device
        FOREIGN KEY (device_id)
        REFERENCES user_devices (device_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_download_status
        CHECK (download_status IN ('Active', 'Expired', 'Deleted')),

    CONSTRAINT chk_file_size_positive
        CHECK (file_size_mb > 0)
);

-- Only one Active download per profile/content/episode/device.
-- episode_id is NULL for movie downloads; NULLs do NOT match each other
-- in PostgreSQL unique indexes, so one index would silently allow duplicate
-- Active movie downloads. Two separate partial indexes close that gap.

-- Covers Series episode downloads (episode_id IS NOT NULL)
CREATE UNIQUE INDEX uix_downloads_active_episode
    ON downloads (profile_id, content_id, episode_id, device_id)
    WHERE download_status = 'Active' AND episode_id IS NOT NULL;

-- Covers Movie downloads (episode_id IS NULL)
CREATE UNIQUE INDEX uix_downloads_active_movie
    ON downloads (profile_id, content_id, device_id)
    WHERE download_status = 'Active' AND episode_id IS NULL;


-- ============================================================
-- TABLE 23: search_history
-- Search query log per profile for analytics and history display.
-- device_id is optional (NULL for web sessions without a tracked device).
-- ============================================================
CREATE TABLE search_history (
    search_id       BIGSERIAL   NOT NULL,
    profile_id      BIGINT      NOT NULL,
    search_query    TEXT        NOT NULL,
    searched_at     TIMESTAMP   NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    result_count    INTEGER     NOT NULL    DEFAULT 0,
    device_id       BIGINT      NULL,

    CONSTRAINT pk_search_history
        PRIMARY KEY (search_id),

    CONSTRAINT fk_search_history_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_search_history_device
        FOREIGN KEY (device_id)
        REFERENCES user_devices (device_id)
        ON DELETE SET NULL,

    CONSTRAINT chk_result_count_non_negative
        CHECK (result_count >= 0)
);


-- ============================================================
-- TABLE 24: profile_preferences
-- Per-profile UX, playback, and notification preferences.
-- Exactly one row per profile (UNIQUE on profile_id FK).
-- language, autoplay_next, autoplay_previews now live here
-- (moved in from profiles, since they're playback preferences).
-- ============================================================
CREATE TABLE profile_preferences (
    preference_id       BIGSERIAL       NOT NULL,
    profile_id          BIGINT          NOT NULL,
    audio_language      CHAR(5)         NOT NULL    DEFAULT 'en',
    default_quality     VARCHAR(10)     NOT NULL    DEFAULT 'auto',
    notifications_on    BOOLEAN         NOT NULL    DEFAULT TRUE,
    new_releases_notif  BOOLEAN         NOT NULL    DEFAULT TRUE,
    continue_watching   BOOLEAN         NOT NULL    DEFAULT TRUE,
    ui_theme            VARCHAR(10)     NOT NULL    DEFAULT 'dark',
    language             CHAR(5)         NOT NULL    DEFAULT 'en',
    autoplay_next         BOOLEAN         NOT NULL    DEFAULT TRUE,
    autoplay_previews     BOOLEAN         NOT NULL    DEFAULT TRUE,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_profile_preferences
        PRIMARY KEY (preference_id),

    CONSTRAINT fk_profile_preferences_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    -- One preferences row per profile only
    CONSTRAINT uq_profile_preferences_profile
        UNIQUE (profile_id),

    CONSTRAINT chk_default_quality
        CHECK (default_quality IN ('auto', 'low', 'medium', 'high', 'ultra')),

    CONSTRAINT chk_ui_theme
        CHECK (ui_theme IN ('dark', 'light', 'system'))
);


-- ============================================================
-- TABLE 25: profile_preferred_genres
-- FK-safe junction table for a profile's preferred genres,
-- consistent with how content_genres already works.
-- ============================================================
CREATE TABLE profile_preferred_genres (
    profile_id  BIGINT  NOT NULL,
    genre_id    BIGINT  NOT NULL,

    CONSTRAINT pk_profile_preferred_genres
        PRIMARY KEY (profile_id, genre_id),

    CONSTRAINT fk_ppg_profile
        FOREIGN KEY (profile_id)
        REFERENCES profiles (profile_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_ppg_genre
        FOREIGN KEY (genre_id)
        REFERENCES genres (genre_id)
        ON DELETE CASCADE
);


COMMIT;

-- ============================================================
-- SUMMARY
-- ============================================================
-- Tables created (25 total):
--
-- CONTENT & CATALOG MODULE (11 tables)
--  1.  genres                   — genre tags (lookup)
--  2.  languages                — language codes (lookup)
--  3.  actors                   — talent master records
--  4.  content                  — movie / series master catalogue
--  5.  seasons                  — seasons per series
--  6.  episodes                 — episodes per season
--  7.  content_parts            — parts of a multi-part movie
--  8.  content_genres           — M:M content ↔ genres
--  9.  content_languages        — audio/subtitle tracks per title
-- 10.  content_cast             — M:M content ↔ actors (with character)
-- 11.  content_availability     — country + date window per title
--
-- USERS & ACCOUNTS MODULE (9 tables)
-- 12.  users                    — core account (identity + login)
-- 13.  profiles                 — sub-profiles under one account
-- 14.  subscription_plans       — plan tiers + feature entitlements
-- 15.  plan_allowed_devices     — M:M plans ↔ supported device types
-- 16.  subscriptions            — user ↔ plan link (active + history)
-- 17.  payments                 — billing transactions + refunds
-- 18.  user_devices             — registered devices per user
-- 19.  ratings                  — like/dislike + review, at title/season/episode/part level
-- 24.  profile_preferences      — per-profile UX/playback settings
--
-- ENGAGEMENT MODULE (5 tables)
-- 20.  watch_history            — append-only viewing session log
-- 21.  my_list                  — saved-for-later watchlist
-- 22.  downloads                — offline downloads per profile/device
-- 23.  search_history           — search query log per profile
-- 25.  profile_preferred_genres — M:M profiles ↔ genres
--
-- Partial unique indexes (9):
--   uix_content_languages_default          — 1 default track per type per title
--   uix_profiles_one_primary_per_user      — 1 primary profile per user
--   uix_subscriptions_one_active_per_user  — 1 active subscription per user
--   uix_downloads_active_episode           — 1 active episode download per device/content
--   uix_downloads_active_movie             — 1 active movie download per device/content
--                                            (split because NULL episode_id bypasses
--                                             uniqueness in a single index)
--   uix_ratings_content_level              — 1 rating per profile per whole title
--   uix_ratings_season_level               — 1 rating per profile per season
--   uix_ratings_episode_level              — 1 rating per profile per episode
--   uix_ratings_part_level                 — 1 rating per profile per movie part
--
-- Application-layer responsibilities:
--   • Profile count ≤ subscription_plans.max_profiles per user
--   • episode_id → content_id consistency in watch_history & downloads
--   • season_id/episode_id/part_id → content_id consistency in ratings
--   • content_parts rows should only exist for content_type = 'Movie'
--   • account_status auto-promotion (pending → active) on email_verified = TRUE
--   • next_billing_date logic on subscription status changes
--   • Device-type entitlement check against plan_allowed_devices before
--     allowing a new user_devices row / stream to start
--   • No age-rating gating in this version (content_rating_levels removed)
-- ============================================================
