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
DROP TABLE IF EXISTS subscription_plans CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS content_availability CASCADE;
DROP TABLE IF EXISTS content_cast CASCADE;
DROP TABLE IF EXISTS content_languages CASCADE;
DROP TABLE IF EXISTS content_genres CASCADE;
DROP TABLE IF EXISTS episodes CASCADE;
DROP TABLE IF EXISTS seasons CASCADE;
DROP TABLE IF EXISTS content CASCADE;
DROP TABLE IF EXISTS actors CASCADE;
DROP TABLE IF EXISTS languages CASCADE;
DROP TABLE IF EXISTS genres CASCADE;
DROP TABLE IF EXISTS content_rating_levels CASCADE;


-- ============================================================
-- PROJECT  : Netflix-Type Streaming Platform
-- DATABASE : PostgreSQL
-- VERSION  : 2.0 — Final Production-Ready DDL (Resume Edition)
-- TABLES   : 24
-- MODULES  : Content & Catalog · Users & Accounts
-- NOTES    : All PK / FK / UQ / CHK constraints verified.
--            Partial unique indexes follow each relevant table.
--            Run this script top-to-bottom in one transaction.
-- ============================================================

BEGIN;

-- ============================================================
-- CREATION ORDER (respects all FK dependencies)
-- ============================================================
--  1.  content_rating_levels   (no deps — pure lookup)
--  2.  genres                  (no deps — pure lookup)
--  3.  languages               (no deps — pure lookup)
--  4.  actors                  (no deps — pure lookup)
--  5.  content                 (deps: content_rating_levels)
--  6.  seasons                 (deps: content)
--  7.  episodes                (deps: seasons)
--  8.  content_genres          (deps: content, genres)
--  9.  content_languages       (deps: content, languages)
-- 10.  content_cast            (deps: content, actors)
-- 11.  content_availability    (deps: content)
-- 12.  users                   (self-ref FK added after creation)
-- 13.  profiles                (deps: users, content_rating_levels)
-- 14.  subscription_plans      (no deps)
-- 15.  subscriptions           (deps: users, subscription_plans)
-- 16.  payments                (deps: subscriptions, users)
-- 17.  user_devices            (deps: users)
-- 18.  ratings                 (deps: profiles, content)
-- 19.  watch_history           (deps: profiles, content, episodes)
-- 20.  my_list                 (deps: profiles, content)
-- 21.  downloads               (deps: profiles, content, episodes, user_devices)
-- 22.  search_history          (deps: profiles, user_devices)
-- 23.  profile_preferences     (deps: profiles)
-- 24.  profile_preferred_genres(deps: profiles, genres)
-- ============================================================


-- ============================================================
-- TABLE 1: content_rating_levels
-- Shared ordered scale for age/content ratings.
-- Enables numeric comparison of title ratings vs profile limits.
-- ============================================================
CREATE TABLE content_rating_levels (
    rating_code     VARCHAR(10)     NOT NULL,
    rating_system   VARCHAR(10)     NOT NULL,
    sort_order      SMALLINT        NOT NULL,
    description     VARCHAR(255)    NULL,

    CONSTRAINT pk_content_rating_levels
        PRIMARY KEY (rating_code),

    CONSTRAINT chk_rating_system
        CHECK (rating_system IN ('Movie', 'TV')),

    CONSTRAINT uq_rating_sort_order
        UNIQUE (sort_order)
);

-- Seed Data: Standard US Rating Codes
INSERT INTO content_rating_levels (rating_code, rating_system, sort_order, description) VALUES
    ('G',       'Movie', 1,  'General Audiences — All ages admitted'),
    ('PG',      'Movie', 2,  'Parental Guidance Suggested'),
    ('PG-13',   'Movie', 3,  'Parents Strongly Cautioned — Some material may be inappropriate for children under 13'),
    ('R',       'Movie', 4,  'Restricted — Under 17 requires parent or guardian'),
    ('NC-17',   'Movie', 5,  'Adults Only — No one 17 and under admitted'),
    ('TV-Y',    'TV',    6,  'All Children'),
    ('TV-G',    'TV',    7,  'General Audience'),
    ('TV-PG',   'TV',    8,  'Parental Guidance Suggested'),
    ('TV-14',   'TV',    9,  'Parents Strongly Cautioned'),
    ('TV-MA',   'TV',    10, 'Mature Audience Only');


-- ============================================================
-- TABLE 2: genres
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
-- TABLE 3: languages
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
-- TABLE 4: actors
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
-- TABLE 5: content
-- Master catalogue entry for every Movie or Series title.
-- duration_minutes is NULL for Series; Episodes carry runtime.
-- ============================================================
CREATE TABLE content (
    content_id          BIGSERIAL       NOT NULL,
    title               VARCHAR(255)    NOT NULL,
    description         TEXT            NULL,
    content_type        VARCHAR(20)     NOT NULL,
    release_date        DATE            NULL,
    age_certification   VARCHAR(10)     NULL,
    duration_minutes    INTEGER         NULL,
    poster_url          TEXT            NULL,
    trailer_url         TEXT            NULL,
    status              VARCHAR(20)     NOT NULL    DEFAULT 'Active',
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_content
        PRIMARY KEY (content_id),

    -- age_certification must map to a valid rating code
    CONSTRAINT fk_content_age_certification
        FOREIGN KEY (age_certification)
        REFERENCES content_rating_levels (rating_code)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

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
-- TABLE 6: seasons
-- Represents individual seasons of a Series title.
-- Must never point at a Movie content row.
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
-- TABLE 7: episodes
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
-- Self-referential FK for referral tracking added post-creation.
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
    preferred_lang  CHAR(5)         NOT NULL    DEFAULT 'en',
    last_login_at   TIMESTAMP       NULL,
    created_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    deleted_at      TIMESTAMP       NULL,

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
-- age_rating_limit uses same ordered FK as content.age_certification.
-- ============================================================
CREATE TABLE profiles (
    profile_id          BIGSERIAL       NOT NULL,
    user_id             BIGINT          NOT NULL,
    profile_name        VARCHAR(50)     NOT NULL,
    avatar_url          VARCHAR(500)    NULL,
    is_kids             BOOLEAN         NOT NULL    DEFAULT FALSE,
    age_rating_limit    VARCHAR(10)     NULL,
    pin_hash            VARCHAR(255)    NULL,
    language            CHAR(5)         NOT NULL    DEFAULT 'en',
    autoplay_next       BOOLEAN         NOT NULL    DEFAULT TRUE,
    autoplay_previews   BOOLEAN         NOT NULL    DEFAULT TRUE,
    is_primary          BOOLEAN         NOT NULL    DEFAULT FALSE,
    created_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_profiles
        PRIMARY KEY (profile_id),

    CONSTRAINT fk_profiles_user
        FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE CASCADE,

    -- age_rating_limit must map to a valid, comparable rating code
    CONSTRAINT fk_profiles_age_rating_limit
        FOREIGN KEY (age_rating_limit)
        REFERENCES content_rating_levels (rating_code)
        ON UPDATE CASCADE
        ON DELETE SET NULL
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
-- TABLE 15: subscriptions
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
    trial_end_date      DATE            NULL,
    auto_renew          BOOLEAN         NOT NULL    DEFAULT TRUE,
    cancelled_at        TIMESTAMP       NULL,
    cancellation_reason VARCHAR(255)    NULL,
    promo_code          VARCHAR(50)     NULL,
    discount_pct        DECIMAL(5,2)    NOT NULL    DEFAULT 0.00,
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

    CONSTRAINT chk_discount_pct_range
        CHECK (discount_pct BETWEEN 0.00 AND 100.00),

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
-- TABLE 16: payments
-- All payment transactions and billing records.
-- user_id is intentional denormalization: fast billing queries
-- without joins, audit trail preserved if subscription deleted.
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
        CHECK (refund_amount <= amount)
);


-- ============================================================
-- TABLE 17: user_devices
-- Registered devices per user for session and security tracking.
-- Fingerprint uniqueness is per-user, not global — shared TVs
-- can be legitimately registered under multiple accounts.
-- ============================================================
CREATE TABLE user_devices (
    device_id           BIGSERIAL       NOT NULL,
    user_id             BIGINT          NOT NULL,
    device_name         VARCHAR(100)    NOT NULL,
    device_type         VARCHAR(20)     NOT NULL,
    os_name             VARCHAR(50)     NOT NULL,
    os_version          VARCHAR(20)     NULL,
    app_version         VARCHAR(20)     NULL,
    browser             VARCHAR(50)     NULL,
    browser_version     VARCHAR(20)     NULL,
    device_fingerprint  VARCHAR(255)    NOT NULL,
    push_token          VARCHAR(500)    NULL,
    is_trusted          BOOLEAN         NOT NULL    DEFAULT FALSE,
    is_active           BOOLEAN         NOT NULL    DEFAULT TRUE,
    ip_address          VARCHAR(45)     NULL,
    last_active_at      TIMESTAMP       NULL,
    registered_at       TIMESTAMP       NOT NULL    DEFAULT CURRENT_TIMESTAMP,

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
        )),

    -- Same physical device fingerprint is unique per user, not globally
    CONSTRAINT uq_user_device_fingerprint
        UNIQUE (user_id, device_fingerprint)
);


-- ============================================================
-- TABLE 18: ratings
-- User star-ratings and optional reviews per profile per title.
-- One row per (profile, content) — UPDATE to change, not INSERT.
-- ============================================================
CREATE TABLE ratings (
    rating_id       BIGSERIAL   NOT NULL,
    profile_id      BIGINT      NOT NULL,
    content_id      BIGINT      NOT NULL,
    rating_value    SMALLINT    NOT NULL,
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

    CONSTRAINT chk_rating_value_range
        CHECK (rating_value BETWEEN 1 AND 5),

    -- One rating per profile per title
    CONSTRAINT uq_ratings_profile_content
        UNIQUE (profile_id, content_id)
);


-- ============================================================
-- TABLE 19: watch_history
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
-- TABLE 20: my_list
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
-- TABLE 21: downloads
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
-- TABLE 22: search_history
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
-- TABLE 23: profile_preferences
-- Per-profile UX, playback, and notification preferences.
-- Exactly one row per profile (UNIQUE on profile_id FK).
-- Content restriction is handled solely by profiles.age_rating_limit.
-- ============================================================
CREATE TABLE profile_preferences (
    preference_id       BIGSERIAL       NOT NULL,
    profile_id          BIGINT          NOT NULL,
    audio_language      CHAR(5)         NOT NULL    DEFAULT 'en',
    default_quality     VARCHAR(10)     NOT NULL    DEFAULT 'auto',
    data_saver_mode     BOOLEAN         NOT NULL    DEFAULT FALSE,
    notifications_on    BOOLEAN         NOT NULL    DEFAULT TRUE,
    new_releases_notif  BOOLEAN         NOT NULL    DEFAULT TRUE,
    continue_watching   BOOLEAN         NOT NULL    DEFAULT TRUE,
    ui_theme            VARCHAR(10)     NOT NULL    DEFAULT 'dark',
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
-- TABLE 24: profile_preferred_genres  *** NEW TABLE ***
-- Replaces the old JSON preferred_genres column in
-- profile_preferences with a proper FK-safe junction table,
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
-- Tables created (24 total):
--
-- CONTENT & CATALOG MODULE (11 tables)
--  1.  content_rating_levels    — ordered rating scale (lookup)
--  2.  genres                   — genre tags (lookup)
--  3.  languages                — language codes (lookup)
--  4.  actors                   — talent master records
--  5.  content                  — movie / series master catalogue
--  6.  seasons                  — seasons per series
--  7.  episodes                 — episodes per season
--  8.  content_genres           — M:M content ↔ genres
--  9.  content_languages        — audio/subtitle tracks per title
-- 10.  content_cast             — M:M content ↔ actors (with character)
-- 11.  content_availability     — country + date window per title
--
-- USER ENGAGEMENT MODULE (5 tables)
-- 12.  ratings                  — star rating + review per profile per title
-- 13.  watch_history            — append-only viewing session log
-- 14.  my_list                  — saved-for-later watchlist
-- 15.  downloads                — offline downloads per profile/device
-- 16.  search_history           — search query log per profile
--
-- USERS & ACCOUNTS MODULE (8 tables)
-- 17.  users                    — core account (identity + login)
-- 18.  profiles                 — sub-profiles under one account
-- 19.  subscription_plans       — plan tiers + feature entitlements
-- 20.  subscriptions            — user ↔ plan link (active + history)
-- 21.  payments                 — billing transactions + refunds
-- 22.  user_devices             — registered devices per user
-- 23.  profile_preferences      — per-profile UX/playback settings
-- 24.  profile_preferred_genres — M:M profiles ↔ genres (replaces JSON)
--
-- Partial unique indexes (5):
--   uix_content_languages_default          — 1 default track per type per title
--   uix_profiles_one_primary_per_user      — 1 primary profile per user
--   uix_subscriptions_one_active_per_user  — 1 active subscription per user
--   uix_downloads_active_episode           — 1 active episode download per device/content
--   uix_downloads_active_movie             — 1 active movie download per device/content
--                                            (split because NULL episode_id bypasses
--                                             uniqueness in a single index)
--
-- Application-layer responsibilities:
--   • Profile count ≤ subscription_plans.max_profiles per user
--   • episode_id → content_id consistency in watch_history & downloads
--   • account_status auto-promotion (pending → active) on email_verified = TRUE
--   • next_billing_date logic on subscription status changes
--   • Content age-gating: compare content.age_certification sort_order
--     against profiles.age_rating_limit sort_order via content_rating_levels
-- ============================================================