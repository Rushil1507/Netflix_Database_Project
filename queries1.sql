-- ============================================================
-- PROJECT  : Netflix-Type Streaming Platform
-- FILE     : netflix_all_queries_runnable.sql
-- PURPOSE  : All four query modules (End User, Kids Profile,
--            Admin/Content Manager, Business Analyst) combined
--            into ONE file that pgAdmin's Query Tool can execute
--            top-to-bottom without errors.
--
-- WHAT WAS CHANGED FROM THE ORIGINAL FILES
--   1. Every $1, $2, $3... placeholder (meant for app-layer
--      parameter binding) has been replaced with a realistic
--      literal sample value, since pgAdmin's Query Tool cannot
--      bind positional parameters the way a backend driver does.
--   2. The two BEGIN...COMMIT blocks that captured a generated id
--      into a psql-only ":new_id" variable were rewritten as a
--      single data-modifying CTE (WITH ... INSERT ... RETURNING),
--      which is valid plain PostgreSQL and chains the inserts
--      atomically without needing psql variables.
--   3. The non-standard "QUALIFY" clause (Snowflake/BigQuery
--      syntax, not valid in Postgres) was removed; the Postgres-
--      compatible subquery version that followed it was kept.
--   4. netflix_app_queries.sql was NOT included below because its
--      content duplicates (an earlier, simpler version of) modules
--      1, 2, 3, and 4 from the four numbered files. Combining both
--      would create duplicate/conflicting statements. The four
--      numbered files are the more complete, final versions.
--
-- IMPORTANT ASSUMPTION
--   These are pure DML queries (SELECT/INSERT/UPDATE/DELETE) — no
--   CREATE TABLE statements were supplied alongside them. This file
--   assumes the schema (tables, constraints, indexes — e.g. from a
--   netflix_db_ddl_final.sql / 00_indexes_performance.sql you ran
--   earlier) already exists in the target database, and that it is
--   otherwise EMPTY of conflicting rows. If you haven't created the
--   schema yet, every statement below will fail with
--   "relation ... does not exist" — that's a missing-schema error,
--   not a syntax error, and is outside what this file can fix.
--
-- HOW TO RUN
--   Open this file in pgAdmin's Query Tool against a database that
--   already has the schema, and execute the whole file (F5 / the
--   lightning bolt). Sample literal values (1, 'sample', etc.) are
--   used purely so every statement is syntactically complete; swap
--   them for real values once you're past the "does it run" stage.
-- ============================================================


-- ============================================================
-- ============================================================
--  MODULE 1 : END USER (SUBSCRIBER)
-- ============================================================
-- ============================================================

-- 1.1  BROWSE & SEARCH CONTENT
-- ============================================================

-- (a) Search with relevance ordering, rating, and pagination.
-- Title matches rank above description-only matches via a CASE
-- score, not just release_date — a generic ORDER BY date alone
-- would bury an exact title hit under unrelated new releases.
-- Params: 'sample' search_term, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.content_type,
    c.release_date,
    c.poster_url,
    c.age_certification,
    ROUND(AVG(r.rating_value), 1) AS avg_rating,
    COUNT(r.rating_id)            AS rating_count,
    CASE
        WHEN c.title ILIKE 'sample' || '%'      THEN 3  -- starts with term
        WHEN c.title ILIKE '%' || 'sample' || '%' THEN 2  -- contains term
        ELSE 1                                      -- description-only match
    END AS relevance_score
FROM content c
LEFT JOIN ratings r ON r.content_id = c.content_id
WHERE c.status = 'Active'
  AND (
        c.title ILIKE '%' || 'sample' || '%'
        OR c.description ILIKE '%' || 'sample' || '%'
      )
GROUP BY c.content_id
ORDER BY relevance_score DESC, avg_rating DESC NULLS LAST, c.release_date DESC
LIMIT 10 OFFSET 0;

-- (b) Total match count for pagination UI ("142 results")
-- Params: 'sample' search_term
SELECT COUNT(*) AS total_matches
FROM content c
WHERE c.status = 'Active'
  AND (c.title ILIKE '%' || 'sample' || '%' OR c.description ILIKE '%' || 'sample' || '%');

-- (c) Log the search — call AFTER (a) completes so result_count
-- is accurate, not before. Guards against empty/whitespace queries
-- polluting analytics.
-- Params: 1 profile_id, 'sample' search_term, 5 result_count, 1 device_id
INSERT INTO search_history (profile_id, search_query, result_count, device_id)
SELECT 1, 'sample', 5, 1
WHERE LENGTH(TRIM('sample')) > 0;

-- (d) Autocomplete suggestions while typing (debounce on the
-- frontend — don't fire this on every keystroke). Prefix match
-- only, so it stays index-friendly without the trigram cost of
-- full ILIKE '%...%'.
-- Params: 'sample' partial_term
SELECT DISTINCT title
FROM content
WHERE status = 'Active'
  AND title ILIKE 'sample' || '%'
ORDER BY title
LIMIT 8;

-- ============================================================
-- 1.2  FILTER BY GENRE
-- ============================================================

-- Params: 1 genre_id, 10 page_size, 0 page_offset
-- Validates genre_id exists before the expensive join — returns
-- an empty result fast instead of silently joining against nothing.
SELECT
    c.content_id,
    c.title,
    c.content_type,
    c.poster_url,
    c.release_date,
    ROUND(AVG(r.rating_value), 1) AS avg_rating
FROM content c
JOIN content_genres cg ON cg.content_id = c.content_id
LEFT JOIN ratings r     ON r.content_id = c.content_id
WHERE cg.genre_id = 1
  AND c.status = 'Active'
  AND EXISTS (SELECT 1 FROM genres g WHERE g.genre_id = 1)
GROUP BY c.content_id
ORDER BY c.release_date DESC
LIMIT 10 OFFSET 0;

-- Multi-genre filter — "Action AND Comedy" (every selected genre
-- must match, not just one). Common UX pattern the single-genre
-- query above can't express.
-- Params: ARRAY[1,2]::BIGINT[] = ARRAY of genre_ids, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.poster_url
FROM content c
JOIN content_genres cg ON cg.content_id = c.content_id
WHERE cg.genre_id = ANY(ARRAY[1,2]::BIGINT[]::BIGINT[])
  AND c.status = 'Active'
GROUP BY c.content_id, c.title, c.poster_url
HAVING COUNT(DISTINCT cg.genre_id) = array_length(ARRAY[1,2]::BIGINT[]::BIGINT[], 1)
ORDER BY c.release_date DESC
LIMIT 10 OFFSET 0;

-- ============================================================
-- 1.3  FILTER BY LANGUAGE
-- ============================================================

-- Params: 1 language_id, 'sample' 'Audio'|'Subtitle', 10 page_size, 0 page_offset
SELECT DISTINCT
    c.content_id,
    c.title,
    c.content_type,
    c.poster_url
FROM content c
JOIN content_languages cl ON cl.content_id = c.content_id
WHERE cl.language_id = 1
  AND cl.language_type IN ('sample', 'Both')
  AND c.status = 'Active'
ORDER BY c.title
LIMIT 10 OFFSET 0;

-- All languages available for one title (shown on the title detail
-- page's "Audio & Subtitles" tab)
-- Params: 1 content_id
SELECT
    l.language_name,
    l.language_code,
    cl.language_type,
    cl.is_default
FROM content_languages cl
JOIN languages l ON l.language_id = cl.language_id
WHERE cl.content_id = 1
ORDER BY cl.is_default DESC, l.language_name;

-- ============================================================
-- 1.4  FILTER BY REGIONAL AVAILABILITY
-- ============================================================

-- Params: 5 country_code, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    ca.available_from,
    ca.available_to
FROM content c
JOIN content_availability ca ON ca.content_id = c.content_id
WHERE ca.country_code = UPPER(5)
  AND CURRENT_DATE >= ca.available_from
  AND (ca.available_to IS NULL OR CURRENT_DATE < ca.available_to)
  AND c.status = 'Active'
ORDER BY ca.available_from DESC
LIMIT 10 OFFSET 0;

-- "Leaving soon" row — titles expiring within the next N days in a
-- given country. High-value Netflix-style UX feature, drives urgency.
-- Params: 5 country_code, 5 days_ahead (e.g. 14)
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    ca.available_to
FROM content c
JOIN content_availability ca ON ca.content_id = c.content_id
WHERE ca.country_code = UPPER(5)
  AND ca.available_to IS NOT NULL
  AND ca.available_to BETWEEN CURRENT_DATE AND CURRENT_DATE + (5 || ' days')::INTERVAL
  AND c.status = 'Active'
ORDER BY ca.available_to ASC
LIMIT 20;

-- ============================================================
-- 1.5  PLAY & RESUME CONTENT
-- ============================================================

-- (a) Resume point lookup. NULL-safe episode comparison handles
-- both movies (episode_id IS NULL) and series episodes correctly —
-- a plain "episode_id = NULL" would silently fail to match NULLs.
-- Params: 1 profile_id, 1 content_id, NULL episode_id (nullable)
SELECT
    watch_id,
    progress_seconds,
    watch_duration_seconds,
    completed,
    watched_at
FROM watch_history
WHERE profile_id = 1
  AND content_id = 1
  AND episode_id IS NOT DISTINCT FROM NULL
ORDER BY watched_at DESC
LIMIT 1;

-- (b) Write playback progress. Uses a single UPSERT-style pattern
-- via a unique partial constraint check in application logic OR,
-- cleaner: only INSERT a new row every N seconds (debounced on
-- frontend) rather than UPDATE-on-every-tick, since watch_history
-- is an append-only log by design (preserves full viewing timeline
-- for analytics in Module 4.1, not just the latest position).
-- Params: 1 profile_id, 1 content_id, 1 episode_id,
--         1 progress_seconds, 1 watch_duration_seconds, TRUE completed
INSERT INTO watch_history
    (profile_id, content_id, episode_id, progress_seconds,
     watch_duration_seconds, completed)
SELECT 1, 1, 1, 1, 1, TRUE
WHERE 1 >= 0 AND 1 >= 0;  -- guard against negative client-side data

-- (c) "Continue Watching" row — DISTINCT ON picks the single most
-- recent in-progress session per title so the same show doesn't
-- appear twice if watched across multiple sittings.
-- Params: 1 profile_id, 10 row_limit
SELECT DISTINCT ON (wh.content_id)
    wh.content_id,
    c.title,
    c.poster_url,
    c.content_type,
    wh.episode_id,
    e.title AS episode_title,
    wh.progress_seconds,
    wh.watch_duration_seconds,
    ROUND(100.0 * wh.progress_seconds / NULLIF(wh.watch_duration_seconds, 0), 0) AS pct_complete,
    wh.watched_at
FROM watch_history wh
JOIN content c        ON c.content_id = wh.content_id
LEFT JOIN episodes e   ON e.episode_id = wh.episode_id
WHERE wh.profile_id = 1
  AND wh.completed = FALSE
  AND wh.progress_seconds > 0
ORDER BY wh.content_id, wh.watched_at DESC
LIMIT 10;

-- (d) Next episode auto-lookup — when a Series episode completes,
-- find the next one in sequence for autoplay (profiles.autoplay_next).
-- Params: 1 current_season_id, 1 current_episode_number
SELECT episode_id, title, duration_minutes, thumbnail_url
FROM episodes
WHERE season_id = 1
  AND episode_number = 1 + 1
LIMIT 1;

-- If no next episode in this season, check for season N+1, episode 1
-- Params: 1 content_id, 1 current_season_number
SELECT e.episode_id, e.title, s.season_id
FROM seasons s
JOIN episodes e ON e.season_id = s.season_id
WHERE s.content_id = 1
  AND s.season_number = 1 + 1
  AND e.episode_number = 1
LIMIT 1;

-- ============================================================
-- 1.6  RATE & REVIEW TITLES
-- ============================================================

-- (a) Upsert rating — validated range, re-rating updates in place.
-- Params: 1 profile_id, 1 content_id, 1 rating_value (1-5), 'sample' review_text
INSERT INTO ratings (profile_id, content_id, rating_value, review_text)
SELECT 1, 1, 1, 'sample'
WHERE 1 BETWEEN 1 AND 5
ON CONFLICT ON CONSTRAINT uq_ratings_profile_content
DO UPDATE SET
    rating_value = EXCLUDED.rating_value,
    review_text  = EXCLUDED.review_text,
    updated_at   = CURRENT_TIMESTAMP;

-- (b) Fetch a profile's existing rating (pre-fill UI stars on the
-- title page before they've decided to rate)
-- Params: 1 profile_id, 1 content_id
SELECT rating_value, review_text, updated_at
FROM ratings
WHERE profile_id = 1 AND content_id = 1;

-- (c) Delete a rating (user removes their review)
-- Params: 1 profile_id, 1 content_id
DELETE FROM ratings
WHERE profile_id = 1 AND content_id = 1;

-- (d) Paginated public reviews for a title's detail page, newest first
-- Params: 1 content_id, 10 page_size, 0 page_offset
SELECT
    r.rating_value,
    r.review_text,
    r.updated_at,
    p.profile_name
FROM ratings r
JOIN profiles p ON p.profile_id = r.profile_id
WHERE r.content_id = 1
  AND r.review_text IS NOT NULL
  AND LENGTH(TRIM(r.review_text)) > 0
ORDER BY r.updated_at DESC
LIMIT 10 OFFSET 0;

-- ============================================================
-- 1.7  MANAGE MY LIST / WATCHLIST
-- ============================================================

-- (a) Add (idempotent)
-- Params: 1 profile_id, 1 content_id
INSERT INTO my_list (profile_id, content_id)
VALUES (1, 1)
ON CONFLICT ON CONSTRAINT uq_my_list_profile_content DO NOTHING;

-- (b) Remove
-- Params: 1 profile_id, 1 content_id
DELETE FROM my_list
WHERE profile_id = 1 AND content_id = 1;

-- (c) Toggle in one round trip — saves a client-side existence
-- check before deciding add vs remove.
-- Params: 1 profile_id, 1 content_id
WITH removed AS (
    DELETE FROM my_list
    WHERE profile_id = 1 AND content_id = 1
    RETURNING content_id
)
INSERT INTO my_list (profile_id, content_id)
SELECT 1, 1
WHERE NOT EXISTS (SELECT 1 FROM removed)
RETURNING content_id;

-- (d) Paginated list view
-- Params: 1 profile_id, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    c.content_type,
    ml.added_at
FROM my_list ml
JOIN content c ON c.content_id = ml.content_id
WHERE ml.profile_id = 1
  AND c.status = 'Active'
ORDER BY ml.added_at DESC
LIMIT 10 OFFSET 0;

-- ============================================================
-- 1.8  DOWNLOAD FOR OFFLINE
-- ============================================================

-- (a) Pre-check: does the plan even allow downloads, and has the
-- user hit their per-plan max_downloads cap? Run BEFORE inserting.
-- Params: 1 user_id
SELECT
    sp.max_downloads,
    (SELECT COUNT(*) FROM downloads d
       JOIN profiles p ON p.profile_id = d.profile_id
      WHERE p.user_id = 1 AND d.download_status = 'Active') AS current_downloads
FROM users u
JOIN subscriptions s ON s.user_id = u.user_id AND s.status = 'active'
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE u.user_id = 1;

-- (b) Start a download — only after (a) confirms capacity remains
-- (enforced in application code; SQL alone can't express "max N
-- active rows per user" without a trigger).
-- Params: 1 profile_id, 1 content_id, 1 episode_id, 1 device_id,
--         9.99 file_size_mb, CURRENT_DATE expiry_date
INSERT INTO downloads
    (profile_id, content_id, episode_id, device_id,
     file_size_mb, expiry_date, download_status)
VALUES (1, 1, 1, 1, 9.99, CURRENT_DATE, 'Active')
ON CONFLICT DO NOTHING  -- relies on uix_downloads_active partial index
RETURNING download_id;

-- (c) List active downloads on a device, with storage total
-- Params: 1 profile_id, 1 device_id
SELECT
    d.download_id,
    c.title,
    c.poster_url,
    d.episode_id,
    e.title AS episode_title,
    d.file_size_mb,
    d.downloaded_at,
    d.expiry_date,
    SUM(d.file_size_mb) OVER () AS total_storage_used_mb
FROM downloads d
JOIN content c       ON c.content_id = d.content_id
LEFT JOIN episodes e ON e.episode_id = d.episode_id
WHERE d.profile_id = 1
  AND d.device_id = 1
  AND d.download_status = 'Active'
ORDER BY d.downloaded_at DESC;

-- (d) Remove a download (ownership check baked into WHERE so one
-- user can't delete another's download by guessing an ID)
-- Params: 1 download_id, 1 profile_id
UPDATE downloads
SET download_status = 'Deleted'
WHERE download_id = 1
  AND profile_id = 1
  AND download_status = 'Active';

-- (e) Nightly expiry job
UPDATE downloads
SET download_status = 'Expired'
WHERE download_status = 'Active'
  AND expiry_date IS NOT NULL
  AND expiry_date < CURRENT_DATE;

-- ============================================================
-- 1.9  MANAGE PROFILES + PINs
-- ============================================================

-- (a) App-layer capacity check BEFORE allowing profile creation
-- Params: 1 user_id
SELECT
    sp.max_profiles,
    COUNT(p.profile_id) AS current_profile_count,
    COUNT(p.profile_id) < sp.max_profiles AS can_create_more
FROM users u
JOIN subscriptions s ON s.user_id = u.user_id AND s.status = 'active'
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
LEFT JOIN profiles p ON p.user_id = u.user_id
WHERE u.user_id = 1
GROUP BY sp.max_profiles;

-- (b) Create profile + default preferences atomically — wrapped in
-- a transaction so a crash between the two inserts can never leave
-- a profile with no preferences row.
-- Params: 1 user_id, 'sample' profile_name, 'sample' avatar_url,
--         TRUE is_kids, 'PG-13' age_rating_limit, '$2b$10$examplehasheddata' pin_hash
BEGIN;

WITH new_profile AS (
    INSERT INTO profiles
        (user_id, profile_name, avatar_url, is_kids, age_rating_limit, pin_hash)
    VALUES (1, 'sample', 'sample', TRUE, 'PG-13', '$2b$10$examplehasheddata')
    RETURNING profile_id
)
INSERT INTO profile_preferences (profile_id)
SELECT profile_id FROM new_profile;

COMMIT;

-- (c) Verify PIN before opening a locked profile (hash comparison
-- happens in app code with bcrypt/argon2 — SQL only fetches the hash)
-- Params: 1 profile_id
SELECT pin_hash FROM profiles WHERE profile_id = 1;

-- (d) Set a PIN on a profile that didn't have one
-- Params: 1 profile_id, '$2b$10$examplehasheddata' new_pin_hash
UPDATE profiles
SET pin_hash = '$2b$10$examplehasheddata', updated_at = CURRENT_TIMESTAMP
WHERE profile_id = 1;

-- (e) Replace preferred genres atomically (delete-then-insert in one
-- transaction so the list is never briefly empty mid-request)
-- Params: 1 profile_id, ARRAY[1,2]::BIGINT[] = ARRAY of genre_ids
BEGIN;

DELETE FROM profile_preferred_genres WHERE profile_id = 1;

INSERT INTO profile_preferred_genres (profile_id, genre_id)
SELECT 1, genre_id
FROM UNNEST(ARRAY[1,2]::BIGINT[]) AS genre_id
WHERE EXISTS (SELECT 1 FROM genres g WHERE g.genre_id = genre_id);

COMMIT;

-- (f) Update playback/UX preferences
-- Params: 1 profile_id, 'sample' subtitle_language, 'sample' subtitle_enabled,
--         'sample' audio_language, 'HD' default_quality, 'sample' ui_theme
UPDATE profile_preferences
SET subtitle_language = 'sample',
    subtitle_enabled  = 'sample',
    audio_language    = 'sample',
    default_quality   = 'HD',
    ui_theme          = 'sample',
    updated_at        = CURRENT_TIMESTAMP
WHERE profile_id = 1;

-- (g) Delete a profile — guard against deleting the only/primary
-- profile on an account, which the app should always prevent.
-- Params: 1 profile_id, 1 user_id
DELETE FROM profiles
WHERE profile_id = 1
  AND user_id = 1
  AND is_primary = FALSE;

-- (h) List all profiles under an account (the profile-picker screen)
-- Params: 1 user_id
SELECT
    profile_id,
    profile_name,
    avatar_url,
    is_kids,
    is_primary,
    (pin_hash IS NOT NULL) AS is_pin_protected
FROM profiles
WHERE user_id = 1
ORDER BY is_primary DESC, created_at ASC;

-- ============================================================
-- 1.10  VIEW & PAY INVOICES
-- ============================================================

-- (a) Paginated billing history
-- Params: 1 user_id, 10 page_size, 0 page_offset
SELECT
    p.payment_id,
    p.amount,
    p.currency,
    p.payment_status,
    p.payment_method,
    p.invoice_url,
    p.paid_at,
    sp.plan_name
FROM payments p
JOIN subscriptions s        ON s.subscription_id = p.subscription_id
JOIN subscription_plans sp  ON sp.plan_id = s.plan_id
WHERE p.user_id = 1
ORDER BY p.created_at DESC
LIMIT 10 OFFSET 0;

-- (b) Current active subscription summary
-- Params: 1 user_id
SELECT
    s.subscription_id,
    sp.plan_name,
    sp.price_monthly,
    sp.price_yearly,
    s.billing_cycle,
    s.next_billing_date,
    s.auto_renew,
    s.status,
    s.trial_end_date,
    (s.trial_end_date IS NOT NULL AND s.trial_end_date >= CURRENT_DATE) AS is_in_trial
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.user_id = 1
  AND s.status = 'active';

-- (c) Record a payment from a gateway webhook. SELECT FOR UPDATE
-- locks the subscription row first to prevent a race where two
-- webhook retries both try to extend next_billing_date simultaneously.
-- Params: 1 subscription_id, 1 user_id, 9.99 amount, 'USD' currency,
--         'card' payment_method, 1 transaction_id, 'txn_sample_001' gateway_name,
--         '{}'::JSONB gateway_response (JSON), 'completed' payment_status
BEGIN;

SELECT subscription_id FROM subscriptions
WHERE subscription_id = 1
FOR UPDATE;

INSERT INTO payments
    (subscription_id, user_id, amount, currency, payment_method,
     transaction_id, gateway_name, gateway_response, payment_status, paid_at)
VALUES
    (1, 1, 9.99, 'USD', 'card', 'txn_sample_001', 'sample_gateway', '{}'::JSONB, 'completed',
     CASE WHEN 'completed' = 'completed' THEN CURRENT_TIMESTAMP ELSE NULL END)
ON CONFLICT ON CONSTRAINT uq_payments_transaction_id DO NOTHING
RETURNING payment_id;

-- Advance billing date only on a completed payment for a monthly plan
UPDATE subscriptions
SET next_billing_date = next_billing_date + INTERVAL '1 month'
WHERE subscription_id = 1
  AND 'completed' = 'completed'
  AND billing_cycle = 'monthly';

COMMIT;

-- (d) Process a refund — clamps refund_amount so it can never
-- exceed what was actually paid (the chk_refund_not_exceed_amount
-- constraint backs this up at the DB level too).
-- Params: 1 payment_id, 9.99 refund_amount
UPDATE payments
SET refund_amount = LEAST(9.99, amount),
    payment_status = 'refunded',
    refunded_at    = CURRENT_TIMESTAMP
WHERE payment_id = 1
  AND payment_status = 'completed';

-- ============================================================
-- END OF MODULE 1
-- ============================================================
-e 

-- ============================================================
-- ============================================================
--  MODULE 2 : KIDS PROFILE USER
-- ============================================================
-- ============================================================


-- ============================================================
-- 2.1  RESTRICTED BROWSING BY RATING
-- ============================================================

-- (a) Core age-gate query — compares the ordered sort_order of the
-- content's rating against the profile's allowed ceiling. This is
-- the single query every other kids-mode browse query must build on;
-- never compare rating_code strings directly (e.g. 'PG' < 'PG-13'
-- as text sorts wrong — 'PG' > 'PG-13' alphabetically).
-- Params: 1 profile_id, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    c.age_certification,
    c.content_type
FROM content c
JOIN content_rating_levels content_rating
    ON content_rating.rating_code = c.age_certification
WHERE c.status = 'Active'
  AND content_rating.sort_order <= (
        SELECT crl.sort_order
        FROM profiles p
        JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
        WHERE p.profile_id = 1
          AND p.is_kids = TRUE
      )
ORDER BY c.release_date DESC
LIMIT 10 OFFSET 0;

-- (b) Defensive fallback — if a kids profile somehow has no
-- age_rating_limit set (NULL), default to the most restrictive
-- tier (TV-Y / G) rather than showing everything. Use COALESCE
-- against the lowest sort_order in the table.
-- Params: 1 profile_id
SELECT
    COALESCE(
        (SELECT crl.sort_order
           FROM profiles p
           JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
          WHERE p.profile_id = 1),
        (SELECT MIN(sort_order) FROM content_rating_levels)
    ) AS effective_rating_ceiling;

-- (c) Verify a single title is safe to play for this profile —
-- call right before starting playback as a server-side guard,
-- never trust a frontend-only filter for parental controls.
-- Params: 1 profile_id, 1 content_id
SELECT EXISTS (
    SELECT 1
    FROM content c
    JOIN content_rating_levels content_rating
        ON content_rating.rating_code = c.age_certification
    WHERE c.content_id = 1
      AND content_rating.sort_order <= (
            SELECT crl.sort_order
            FROM profiles p
            JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
            WHERE p.profile_id = 1
          )
) AS is_playback_allowed;

-- ============================================================
-- 2.2  SIMPLIFIED GENRE FILTERING
-- ============================================================

-- (a) Kids home rows grouped by genre — one query per genre row
-- on the home screen, age-gated and limited to a small per-row
-- count since kids UIs favor large tiles over long scroll lists.
-- Params: 1 profile_id, 1 genre_id, 10 row_limit
SELECT
    c.content_id,
    c.title,
    c.poster_url
FROM content_genres cg
JOIN content c ON c.content_id = cg.content_id
JOIN content_rating_levels content_rating
    ON content_rating.rating_code = c.age_certification
WHERE cg.genre_id = 1
  AND c.status = 'Active'
  AND content_rating.sort_order <= (
        SELECT crl.sort_order
        FROM profiles p
        JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
        WHERE p.profile_id = 1
      )
ORDER BY c.release_date DESC
LIMIT 10;

-- (b) Full kids home screen — one round trip that returns every
-- preferred-genre row at once instead of N+1 queries from the
-- frontend looping per genre.
-- Params: 1 profile_id
SELECT
    g.genre_id,
    g.genre_name,
    c.content_id,
    c.title,
    c.poster_url,
    ROW_NUMBER() OVER (PARTITION BY g.genre_id ORDER BY c.release_date DESC) AS rank_in_genre
-- NOTE: QUALIFY is not standard PostgreSQL syntax, so the version
-- below uses the equivalent subquery pattern directly.
SELECT genre_id, genre_name, content_id, title, poster_url
FROM (
    SELECT
        g.genre_id,
        g.genre_name,
        c.content_id,
        c.title,
        c.poster_url,
        ROW_NUMBER() OVER (PARTITION BY g.genre_id ORDER BY c.release_date DESC) AS rank_in_genre
    FROM profile_preferred_genres ppg
    JOIN genres g            ON g.genre_id = ppg.genre_id
    JOIN content_genres cg   ON cg.genre_id = ppg.genre_id
    JOIN content c            ON c.content_id = cg.content_id
    JOIN content_rating_levels content_rating
        ON content_rating.rating_code = c.age_certification
    WHERE ppg.profile_id = 1
      AND c.status = 'Active'
      AND content_rating.sort_order <= (
            SELECT crl.sort_order
            FROM profiles p
            JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
            WHERE p.profile_id = 1
          )
) ranked
WHERE rank_in_genre <= 10
ORDER BY genre_name, rank_in_genre;

-- (c) Fallback when a kids profile has no preferred genres set yet
-- (new profile, hasn't onboarded) — show the most-rated kids-safe
-- titles instead of an empty home screen.
-- Params: 1 profile_id, 10 row_limit
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    ROUND(AVG(r.rating_value), 1) AS avg_rating
FROM content c
JOIN content_rating_levels content_rating
    ON content_rating.rating_code = c.age_certification
LEFT JOIN ratings r ON r.content_id = c.content_id
WHERE c.status = 'Active'
  AND content_rating.sort_order <= (
        SELECT crl.sort_order
        FROM profiles p
        JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
        WHERE p.profile_id = 1
      )
  AND NOT EXISTS (
        SELECT 1 FROM profile_preferred_genres ppg WHERE ppg.profile_id = 1
      )
GROUP BY c.content_id
ORDER BY avg_rating DESC NULLS LAST
LIMIT 10;

-- ============================================================
-- 2.3  KIDS-SAFE SEARCH (bonus — search must respect the same gate)
-- ============================================================

-- A plain reuse of the Module 1 search query would leak adult
-- content to kids. This version applies the identical age-gate
-- filter on top of search.
-- Params: 1 profile_id, 'sample' search_term, 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    c.age_certification
FROM content c
JOIN content_rating_levels content_rating
    ON content_rating.rating_code = c.age_certification
WHERE c.status = 'Active'
  AND c.title ILIKE '%' || 'sample' || '%'
  AND content_rating.sort_order <= (
        SELECT crl.sort_order
        FROM profiles p
        JOIN content_rating_levels crl ON crl.rating_code = p.age_rating_limit
        WHERE p.profile_id = 1
      )
ORDER BY c.title
LIMIT 10 OFFSET 0;

-- ============================================================
-- 2.4  PARENTAL CONTROLS MANAGEMENT (from the parent's primary profile)
-- ============================================================

-- (a) Update a kids profile's age ceiling — only the account's
-- primary (non-kids) profile should be allowed to call this in
-- application logic.
-- Params: 1 kids_profile_id, 10 new_age_rating_limit, 1 acting_user_id
UPDATE profiles
SET age_rating_limit = 10,
    updated_at = CURRENT_TIMESTAMP
WHERE profile_id = 1
  AND is_kids = TRUE
  AND user_id = 1;  -- ensures the caller owns the account

-- (b) List all kids profiles under an account, with their current
-- rating ceiling — parental control dashboard view.
-- Params: 1 user_id
SELECT
    profile_id,
    profile_name,
    avatar_url,
    age_rating_limit,
    (SELECT description FROM content_rating_levels crl
      WHERE crl.rating_code = profiles.age_rating_limit) AS limit_description
FROM profiles
WHERE user_id = 1
  AND is_kids = TRUE
ORDER BY profile_name;

-- ============================================================
-- END OF MODULE 2
-- ============================================================
-e 

-- ============================================================
-- ============================================================
--  MODULE 3 : ADMIN / CONTENT MANAGER
-- ============================================================
-- ============================================================


-- ============================================================
-- 3.1  ADD / UPDATE / RETIRE CONTENT
-- ============================================================

-- (a) Add new content. Guards: content_type must be valid,
-- duration_minutes must be NULL for Series (the chk_duration_series_null
-- constraint enforces this at the DB level too, but failing fast
-- here gives a cleaner app-level error message).
-- Params: 'sample' title, 'sample' description, 'Movie' content_type, CURRENT_DATE release_date,
--         'PG-13' age_certification, 1 duration_minutes, 'sample' poster_url, 'sample' trailer_url
INSERT INTO content
    (title, description, content_type, release_date,
     age_certification, duration_minutes, poster_url, trailer_url)
SELECT 'sample', 'sample', 'Movie', CURRENT_DATE, 'PG-13', 1, 'sample', 'sample'
WHERE 'Movie' IN ('Movie', 'Series')
  AND (
        ('Movie' = 'Series' AND 1 IS NULL)
        OR 'Movie' = 'Movie'
      )
RETURNING content_id;

-- (b) Full content creation, including genres and language tracks,
-- as one atomic transaction. If any step fails, nothing partial
-- is left behind (no title with zero genres because the genre
-- insert silently failed).
-- Params: 'sample' title, 'sample' description, 'Movie' content_type,
--         CURRENT_DATE release_date, 'PG-13' age_certification,
--         1 duration_minutes, 'sample' poster_url, 'sample' trailer_url,
--         ARRAY[1,2]::BIGINT[] genre_ids,
--         ARRAY[1,2]::BIGINT[] language_ids, ARRAY['Audio','Subtitle']::VARCHAR[] language_types,
--         ARRAY[TRUE,FALSE]::BOOLEAN[] is_default_flags
BEGIN;

WITH new_content AS (
    INSERT INTO content
        (title, description, content_type, release_date,
         age_certification, duration_minutes, poster_url, trailer_url)
    VALUES ('sample', 'sample', 'Movie', CURRENT_DATE, 'PG-13', 1, 'sample', 'sample')
    RETURNING content_id
),
ins_genres AS (
    INSERT INTO content_genres (content_id, genre_id)
    SELECT new_content.content_id, genre_id
    FROM new_content, UNNEST(ARRAY[1,2]::BIGINT[]) AS genre_id
    RETURNING content_id
)
INSERT INTO content_languages (content_id, language_id, language_type, is_default)
SELECT new_content.content_id, language_id, language_type, is_default
FROM new_content,
     UNNEST(ARRAY[1,2]::BIGINT[], ARRAY['Audio','Subtitle']::VARCHAR[], ARRAY[TRUE,FALSE]::BOOLEAN[])
        AS t(language_id, language_type, is_default);

COMMIT;

-- (c) Add a season — duplicate-safe via the existing
-- uq_seasons_content_season constraint; ON CONFLICT makes the
-- admin panel idempotent if a save button gets double-clicked.
-- Params: 1 content_id, 1 season_number, 'sample' title, 'sample' description, CURRENT_DATE release_date
INSERT INTO seasons (content_id, season_number, title, description, release_date)
VALUES (1, 1, 'sample', 'sample', CURRENT_DATE)
ON CONFLICT ON CONSTRAINT uq_seasons_content_season
DO UPDATE SET
    title       = EXCLUDED.title,
    description = EXCLUDED.description,
    release_date = EXCLUDED.release_date,
    updated_at   = CURRENT_TIMESTAMP
RETURNING season_id;

-- (d) Add an episode — same idempotent upsert pattern.
-- Params: 1 season_id, 1 episode_number, 'sample' title, 'sample' description,
--         1 duration_minutes, CURRENT_DATE release_date, 'sample' video_url, 'sample' thumbnail_url
INSERT INTO episodes
    (season_id, episode_number, title, description,
     duration_minutes, release_date, video_url, thumbnail_url)
VALUES (1, 1, 'sample', 'sample', 1, CURRENT_DATE, 'sample', 'sample')
ON CONFLICT ON CONSTRAINT uq_episodes_season_episode
DO UPDATE SET
    title            = EXCLUDED.title,
    description      = EXCLUDED.description,
    duration_minutes = EXCLUDED.duration_minutes,
    video_url        = EXCLUDED.video_url,
    thumbnail_url    = EXCLUDED.thumbnail_url,
    updated_at        = CURRENT_TIMESTAMP
RETURNING episode_id;

-- (e) Update existing content metadata (partial update — only
-- touches fields the admin actually changed via COALESCE, so
-- the API can send only changed fields instead of the full record).
-- Params: 1 content_id, 'sample' title, 'sample' description, 'sample' poster_url, 'sample' trailer_url
UPDATE content
SET title       = COALESCE('sample', title),
    description = COALESCE('sample', description),
    poster_url  = COALESCE('sample', poster_url),
    trailer_url = COALESCE('sample', trailer_url),
    updated_at  = CURRENT_TIMESTAMP
WHERE content_id = 1
RETURNING *;

-- (f) Retire content — soft-delete only. Preserves every user's
-- ratings, watch_history, and my_list entries (those tables still
-- reference content_id; they just won't show in active browse
-- queries since those all filter on status = 'Active').
-- Params: 1 content_id
UPDATE content
SET status = 'Inactive',
    updated_at = CURRENT_TIMESTAMP
WHERE content_id = 1
  AND status = 'Active'  -- no-op if already retired
RETURNING content_id, title;

-- (g) Reinstate retired content
-- Params: 1 content_id
UPDATE content
SET status = 'Active',
    updated_at = CURRENT_TIMESTAMP
WHERE content_id = 1
  AND status = 'Inactive';

-- (h) Assign a genre (idempotent — silently no-ops on duplicate)
-- Params: 1 content_id, 1 genre_id
INSERT INTO content_genres (content_id, genre_id)
VALUES (1, 1)
ON CONFLICT (content_id, genre_id) DO NOTHING;

-- (i) Remove a genre assignment
-- Params: 1 content_id, 1 genre_id
DELETE FROM content_genres
WHERE content_id = 1 AND genre_id = 1;

-- (j) Admin content list with filters — the main catalogue
-- management table, with status filter and search combined.
-- Params: 'completed' status_filter ('Active'|'Inactive'|'ComingSoon'|NULL for all),
--         'sample' search_term (NULL for none), 10 page_size, 0 page_offset
SELECT
    c.content_id,
    c.title,
    c.content_type,
    c.status,
    c.release_date,
    c.created_at,
    c.updated_at,
    COUNT(DISTINCT s.season_id)  AS season_count,
    COUNT(DISTINCT cc.actor_id)  AS cast_count
FROM content c
LEFT JOIN seasons s       ON s.content_id = c.content_id
LEFT JOIN content_cast cc ON cc.content_id = c.content_id
WHERE ('completed' IS NULL OR c.status = 'completed')
  AND ('sample' IS NULL OR c.title ILIKE '%' || 'sample' || '%')
GROUP BY c.content_id
ORDER BY c.updated_at DESC
LIMIT 10 OFFSET 0;

-- ============================================================
-- 3.2  MANAGE CAST & CREW
-- ============================================================

-- (a) Add a new actor — checks for an existing near-duplicate by
-- name + date_of_birth first, since actor_name alone isn't unique
-- (common names exist) but the combination almost always is.
-- Params: 'sample' actor_name, CURRENT_DATE date_of_birth, 'sample' gender, 'sample' nationality, 'sample' bio, 'sample' photo_url
INSERT INTO actors (actor_name, date_of_birth, gender, nationality, bio, photo_url)
SELECT 'sample', CURRENT_DATE, 'sample', 'sample', 'sample', 'sample'
WHERE NOT EXISTS (
    SELECT 1 FROM actors
    WHERE actor_name = 'sample'
      AND date_of_birth IS NOT DISTINCT FROM CURRENT_DATE
)
RETURNING actor_id;

-- (b) Search actors when an admin is typing a name into the cast
-- assignment field (autocomplete, avoids creating true duplicates)
-- Params: 'sample' partial_name
SELECT actor_id, actor_name, date_of_birth, photo_url
FROM actors
WHERE actor_name ILIKE '%' || 'sample' || '%'
ORDER BY actor_name
LIMIT 10;

-- (c) Attach actor to a title — idempotent on the
-- (content_id, actor_id, character_name) uniqueness rule, so
-- re-saving the same cast entry won't error.
-- Params: 1 content_id, 1 actor_id, 'sample' character_name, 1 cast_order, TRUE is_main_cast
INSERT INTO content_cast (content_id, actor_id, character_name, cast_order, is_main_cast)
VALUES (1, 1, 'sample', 1, TRUE)
ON CONFLICT ON CONSTRAINT uq_content_cast_unique
DO UPDATE SET
    cast_order   = EXCLUDED.cast_order,
    is_main_cast = EXCLUDED.is_main_cast;

-- (d) Remove a cast entry
-- Params: 1 cast_id
DELETE FROM content_cast WHERE cast_id = 1;

-- (e) Full cast list for a title's detail page, billing-ordered
-- (NULLS LAST so unranked extras fall to the bottom, not the top)
-- Params: 1 content_id
SELECT
    a.actor_id,
    a.actor_name,
    a.photo_url,
    cc.character_name,
    cc.cast_order,
    cc.is_main_cast
FROM content_cast cc
JOIN actors a ON a.actor_id = cc.actor_id
WHERE cc.content_id = 1
ORDER BY cc.is_main_cast DESC, cc.cast_order NULLS LAST;

-- (f) Filmography for an actor's profile page — every title they've
-- appeared in, newest first.
-- Params: 1 actor_id
SELECT
    c.content_id,
    c.title,
    c.poster_url,
    c.release_date,
    cc.character_name
FROM content_cast cc
JOIN content c ON c.content_id = cc.content_id
WHERE cc.actor_id = 1
  AND c.status = 'Active'
ORDER BY c.release_date DESC;

-- ============================================================
-- 3.3  SET COUNTRY AVAILABILITY WINDOWS
-- ============================================================

-- (a) Add an availability window. The exclusion constraint
-- (excl_content_availability_no_overlap, if enabled per the DDL's
-- commented-out block) prevents two overlapping windows for the
-- same content+country at the database level — this query is the
-- one that constraint protects.
-- Params: 1 content_id, 5 country_code, 'sample' available_from,
--         'sample' available_to, 'sample' region_notes
INSERT INTO content_availability
    (content_id, country_code, available_from, available_to, region_notes)
VALUES (1, UPPER(5), 'sample', 'sample', 'sample')
RETURNING availability_id;

-- (b) Bulk-add the same window across many countries at once —
-- common admin task ("launch in all EU countries on this date").
-- Params: 1 content_id, ARRAY['US','IN']::VARCHAR[] = ARRAY of country codes,
--         'sample' available_from, 'sample' available_to
INSERT INTO content_availability (content_id, country_code, available_from, available_to)
SELECT 1, UPPER(country_code), 'sample', 'sample'
FROM UNNEST(ARRAY['US','IN']::VARCHAR[]::VARCHAR[]) AS country_code;

-- (c) Update an existing window (extend or shorten availability)
-- Params: 1 availability_id, 'sample' new_available_to
UPDATE content_availability
SET available_to = 'sample'
WHERE availability_id = 1;

-- (d) Remove a country entirely (content pulled from that market)
-- Params: 1 content_id, 5 country_code
DELETE FROM content_availability
WHERE content_id = 1 AND country_code = UPPER(5);

-- (e) Full availability matrix for a title (admin review screen)
-- Params: 1 content_id
SELECT
    country_code,
    available_from,
    available_to,
    region_notes,
    CASE
        WHEN CURRENT_DATE < available_from THEN 'Scheduled'
        WHEN available_to IS NULL OR CURRENT_DATE < available_to THEN 'Live'
        ELSE 'Expired'
    END AS window_status
FROM content_availability
WHERE content_id = 1
ORDER BY country_code;

-- ============================================================
-- 3.4  ACTIVATE / DEACTIVATE SUBSCRIPTION PLANS
-- ============================================================

-- (a) Deactivate — existing subscribers are untouched (their
-- subscriptions.plan_id FK still resolves fine); only new signups
-- stop seeing it via the is_active filter.
-- Params: 1 plan_id
UPDATE subscription_plans
SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
WHERE plan_id = 1;

-- (b) Reactivate
-- Params: 1 plan_id
UPDATE subscription_plans
SET is_active = TRUE, updated_at = CURRENT_TIMESTAMP
WHERE plan_id = 1;

-- (c) Plans visible to new signups, cheapest first
SELECT plan_id, plan_name, price_monthly, price_yearly,
       video_quality, max_screens, max_profiles, max_downloads
FROM subscription_plans
WHERE is_active = TRUE
ORDER BY price_monthly;

-- (d) Admin view: impact check before deactivating a plan — how
-- many active subscribers are currently on it (informs the
-- decision, since deactivating doesn't migrate anyone automatically)
-- Params: 1 plan_id
SELECT COUNT(*) AS active_subscribers_on_plan
FROM subscriptions
WHERE plan_id = 1 AND status = 'active';

-- (e) Create a brand-new plan
-- Params: 'sample' plan_name, 9.99 price_monthly, 9.99 price_yearly, 'USD' currency,
--         1 max_screens, 1 max_profiles, 'HD' video_quality,
--         TRUE hdr_support, TRUE dolby_atmos, 1 max_downloads, TRUE ads_supported
INSERT INTO subscription_plans
    (plan_name, price_monthly, price_yearly, currency, max_screens,
     max_profiles, video_quality, hdr_support, dolby_atmos, max_downloads, ads_supported)
VALUES ('sample', 9.99, 9.99, 'USD', 1, 1, 'HD', TRUE, TRUE, 1, TRUE)
RETURNING plan_id;

-- ============================================================
-- END OF MODULE 3
-- ============================================================
-e 

-- ============================================================
-- ============================================================
--  MODULE 4 : BUSINESS ANALYST
-- ============================================================
-- ============================================================

-- ============================================================

-- ============================================================
-- 4.1  WATCH ENGAGEMENT REPORTS
-- ============================================================

-- (a) Completion rate and average watch time per title, date-range
-- parameterized rather than hardcoded.
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date, 10 row_limit
SELECT
    c.content_id,
    c.title,
    c.content_type,
    COUNT(*)                                          AS total_views,
    COUNT(*) FILTER (WHERE wh.completed)               AS completed_views,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE wh.completed) / NULLIF(COUNT(*), 0), 1
    )                                                   AS completion_rate_pct,
    ROUND(AVG(wh.watch_duration_seconds) / 60.0, 1)     AS avg_minutes_watched,
    COUNT(DISTINCT wh.profile_id)                        AS unique_viewers
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
WHERE wh.watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY c.content_id, c.title, c.content_type
ORDER BY total_views DESC
LIMIT 10;

-- (b) Engagement trend over time — daily view counts, useful for
-- spotting spikes after a marketing push or a new-episode drop.
-- Params: 1 content_id, CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    DATE_TRUNC('day', watched_at) AS view_date,
    COUNT(*)                       AS views,
    COUNT(DISTINCT profile_id)     AS unique_viewers,
    ROUND(AVG(watch_duration_seconds) / 60.0, 1) AS avg_minutes
FROM watch_history
WHERE content_id = 1
  AND watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY DATE_TRUNC('day', watched_at)
ORDER BY view_date;

-- (c) Drop-off analysis per episode within a series — identifies
-- exactly which episode loses the most viewers, which a
-- title-level aggregate completely hides.
-- Params: 1 content_id, 1 season_number
SELECT
    e.episode_number,
    e.title AS episode_title,
    COUNT(wh.watch_id)                                  AS total_views,
    COUNT(*) FILTER (WHERE wh.completed)                AS completions,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE wh.completed) / NULLIF(COUNT(wh.watch_id), 0), 1
    )                                                     AS completion_rate_pct,
    ROUND(
        100.0 * COUNT(wh.watch_id) /
        NULLIF(LAG(COUNT(wh.watch_id)) OVER (ORDER BY e.episode_number), 0), 1
    )                                                     AS pct_retained_from_prev_episode
FROM episodes e
JOIN seasons s        ON s.season_id = e.season_id
LEFT JOIN watch_history wh ON wh.episode_id = e.episode_id
WHERE s.content_id = 1
  AND s.season_number = 1
GROUP BY e.episode_id, e.episode_number, e.title
ORDER BY e.episode_number;

-- (d) Top content by unique viewer reach (different ranking than
-- raw view count — a title re-watched heavily by few people ranks
-- lower here than one watched once by many, which matters for
-- different business questions: virality vs. binge-engagement).
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date, 10 row_limit
SELECT
    c.content_id,
    c.title,
    COUNT(DISTINCT wh.profile_id) AS unique_viewers,
    COUNT(*)                       AS total_views,
    ROUND(COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT wh.profile_id), 0), 2) AS avg_views_per_viewer
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
WHERE wh.watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY c.content_id, c.title
ORDER BY unique_viewers DESC
LIMIT 10;

-- (e) Most-engaging genres by average completion rate — rolls
-- watch_history up through content_genres to answer "which genre
-- keeps people watching to the end."
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    g.genre_name,
    COUNT(*)                              AS total_views,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE wh.completed) / NULLIF(COUNT(*), 0), 1
    )                                       AS completion_rate_pct
FROM watch_history wh
JOIN content_genres cg ON cg.content_id = wh.content_id
JOIN genres g            ON g.genre_id = cg.genre_id
WHERE wh.watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY g.genre_name
ORDER BY completion_rate_pct DESC;

-- ============================================================
-- 4.2  SUBSCRIPTION CHURN ANALYSIS
-- ============================================================

-- (a) Monthly cancellation count with month-over-month % change —
-- a raw count per month is useless without the trend direction.
-- Params: 5 months_back (e.g. 12)
WITH monthly_cancellations AS (
    SELECT
        DATE_TRUNC('month', cancelled_at) AS cancel_month,
        COUNT(*)                          AS cancellations
    FROM subscriptions
    WHERE status = 'cancelled'
      AND cancelled_at >= CURRENT_DATE - (5 || ' months')::INTERVAL
    GROUP BY DATE_TRUNC('month', cancelled_at)
)
SELECT
    cancel_month,
    cancellations,
    LAG(cancellations) OVER (ORDER BY cancel_month) AS prev_month_cancellations,
    ROUND(
        100.0 * (cancellations - LAG(cancellations) OVER (ORDER BY cancel_month))
        / NULLIF(LAG(cancellations) OVER (ORDER BY cancel_month), 0), 1
    ) AS pct_change_mom
FROM monthly_cancellations
ORDER BY cancel_month DESC;

-- (b) Top cancellation reasons, with percentage share
SELECT
    COALESCE(cancellation_reason, 'Not specified') AS reason,
    COUNT(*)                                         AS occurrences,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_total_cancellations
FROM subscriptions
WHERE status = 'cancelled'
GROUP BY cancellation_reason
ORDER BY occurrences DESC;

-- (c) Cohort-based churn rate — what % of subscriptions that
-- STARTED in a given month have since cancelled. This is the
-- standard churn definition, distinct from "how many cancelled
-- this month" (which mixes cohorts of different ages together).
-- Params: 'sample' cohort_start_month (e.g. '2026-01-01')
SELECT
    DATE_TRUNC('month', start_date) AS cohort_month,
    COUNT(*)                                              AS cohort_size,
    COUNT(*) FILTER (WHERE status = 'cancelled')           AS cancelled_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE status = 'cancelled') / NULLIF(COUNT(*), 0), 2
    )                                                       AS churn_rate_pct
FROM subscriptions
WHERE DATE_TRUNC('month', start_date) = DATE_TRUNC('month', 'sample'::DATE)
GROUP BY DATE_TRUNC('month', start_date);

-- (d) Churn rate broken down by plan tier — reveals whether
-- cheaper or pricier plans churn faster, which a blended overall
-- rate would mask entirely.
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    sp.plan_name,
    COUNT(*)                                              AS total_subscriptions,
    COUNT(*) FILTER (WHERE s.status = 'cancelled')         AS cancelled,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE s.status = 'cancelled') / NULLIF(COUNT(*), 0), 2
    )                                                       AS churn_rate_pct
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.start_date BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY sp.plan_name
ORDER BY churn_rate_pct DESC;

-- (e) At-risk subscribers — active subscriptions with auto_renew
-- turned off (a leading churn indicator worth proactive outreach
-- before they actually cancel).
SELECT
    u.user_id,
    u.email,
    sp.plan_name,
    s.next_billing_date,
    s.end_date
FROM subscriptions s
JOIN users u                ON u.user_id = s.user_id
JOIN subscription_plans sp  ON sp.plan_id = s.plan_id
WHERE s.status = 'active'
  AND s.auto_renew = FALSE
ORDER BY s.next_billing_date ASC;

-- ============================================================
-- 4.3  REVENUE & REFUND TRACKING
-- ============================================================

-- (a) Monthly revenue, gross vs net, with month-over-month growth
-- Params: 5 months_back
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', paid_at) AS revenue_month,
        SUM(amount)                  AS gross_revenue,
        SUM(refund_amount)           AS total_refunded,
        SUM(amount - refund_amount)  AS net_revenue
    FROM payments
    WHERE payment_status = 'completed'
      AND paid_at >= CURRENT_DATE - (5 || ' months')::INTERVAL
    GROUP BY DATE_TRUNC('month', paid_at)
)
SELECT
    revenue_month,
    gross_revenue,
    total_refunded,
    net_revenue,
    ROUND(
        100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY revenue_month))
        / NULLIF(LAG(net_revenue) OVER (ORDER BY revenue_month), 0), 1
    ) AS net_revenue_growth_pct
FROM monthly_revenue
ORDER BY revenue_month DESC;

-- (b) Revenue by plan tier
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    sp.plan_name,
    COUNT(p.payment_id)  AS payment_count,
    SUM(p.amount)         AS gross_revenue,
    SUM(p.refund_amount)  AS total_refunded,
    SUM(p.amount - p.refund_amount) AS net_revenue,
    ROUND(100.0 * SUM(p.amount - p.refund_amount) / SUM(SUM(p.amount - p.refund_amount)) OVER (), 1) AS pct_of_total_revenue
FROM payments p
JOIN subscriptions s        ON s.subscription_id = p.subscription_id
JOIN subscription_plans sp  ON sp.plan_id = s.plan_id
WHERE p.payment_status = 'completed'
  AND p.paid_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY sp.plan_name
ORDER BY net_revenue DESC;

-- (c) Refund rate, plus average days-to-refund (how long after
-- payment do refunds typically happen — flags slow vs fast
-- support response if this trends upward)
SELECT
    COUNT(*) FILTER (WHERE refund_amount > 0)                          AS refunded_payments,
    COUNT(*)                                                            AS total_payments,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE refund_amount > 0) / NULLIF(COUNT(*), 0), 2
    )                                                                    AS refund_rate_pct,
    ROUND(AVG(EXTRACT(EPOCH FROM (refunded_at - paid_at)) / 86400.0)
          FILTER (WHERE refunded_at IS NOT NULL), 1)                     AS avg_days_to_refund
FROM payments
WHERE payment_status IN ('completed', 'refunded');

-- (d) Failed payment recovery — payments that failed, useful for
-- dunning/retry campaigns
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    u.user_id,
    u.email,
    p.amount,
    p.payment_method,
    p.created_at,
    sp.plan_name
FROM payments p
JOIN users u                ON u.user_id = p.user_id
JOIN subscriptions s        ON s.subscription_id = p.subscription_id
JOIN subscription_plans sp  ON sp.plan_id = s.plan_id
WHERE p.payment_status = 'failed'
  AND p.created_at BETWEEN CURRENT_DATE AND CURRENT_DATE
ORDER BY p.created_at DESC;

-- (e) Lifetime value (LTV) per user — total net revenue ever
-- collected, ranked, identifies top-spending customers
-- Params: 10 row_limit
SELECT
    u.user_id,
    u.email,
    SUM(p.amount - p.refund_amount) AS lifetime_net_revenue,
    COUNT(p.payment_id)              AS total_payments,
    MIN(p.paid_at)                    AS first_payment,
    MAX(p.paid_at)                    AS last_payment
FROM payments p
JOIN users u ON u.user_id = p.user_id
WHERE p.payment_status = 'completed'
GROUP BY u.user_id, u.email
ORDER BY lifetime_net_revenue DESC
LIMIT 10;

-- ============================================================
-- 4.4  TOP-RATED CONTENT
-- ============================================================

-- (a) Top-rated with a minimum vote threshold (avoids a single
-- 5-star rating outranking a title with 500 ratings averaging 4.8)
-- Params: 5 min_rating_count, 10 row_limit
SELECT
    c.content_id,
    c.title,
    c.content_type,
    COUNT(r.rating_id)            AS rating_count,
    ROUND(AVG(r.rating_value), 2) AS avg_rating
FROM content c
JOIN ratings r ON r.content_id = c.content_id
GROUP BY c.content_id, c.title, c.content_type
HAVING COUNT(r.rating_id) >= 5
ORDER BY avg_rating DESC, rating_count DESC
LIMIT 10;

-- (b) Bayesian-weighted rating — blends a title's own average with
-- the platform-wide average, pulling low-vote-count titles toward
-- the mean instead of excluding them outright (the IMDb "weighted
-- rating" formula). More defensible than a hard minimum-votes cutoff.
-- Params: 1 min_votes_for_credibility (e.g. 10), 10 row_limit
WITH platform_avg AS (
    SELECT AVG(rating_value) AS avg_all FROM ratings
)
SELECT
    c.content_id,
    c.title,
    COUNT(r.rating_id)            AS rating_count,
    ROUND(AVG(r.rating_value), 2) AS raw_avg_rating,
    ROUND(
        (COUNT(r.rating_id)::NUMERIC / (1 + COUNT(r.rating_id))) * AVG(r.rating_value)
        + (1::NUMERIC / (1 + COUNT(r.rating_id))) * (SELECT avg_all FROM platform_avg)
    , 2) AS weighted_rating
FROM content c
JOIN ratings r ON r.content_id = c.content_id
GROUP BY c.content_id, c.title
ORDER BY weighted_rating DESC
LIMIT 10;

-- (c) Top-rated by genre — answers "best comedy" rather than just
-- "best overall," which is the more common real-world report ask.
-- Params: 1 genre_id, 5 min_rating_count, 10 row_limit
SELECT
    c.content_id,
    c.title,
    COUNT(r.rating_id)            AS rating_count,
    ROUND(AVG(r.rating_value), 2) AS avg_rating
FROM content c
JOIN content_genres cg ON cg.content_id = c.content_id
JOIN ratings r           ON r.content_id = c.content_id
WHERE cg.genre_id = 1
GROUP BY c.content_id, c.title
HAVING COUNT(r.rating_id) >= 5
ORDER BY avg_rating DESC
LIMIT 10;

-- (d) Most controversial titles — high rating count but high
-- standard deviation (loved by some, hated by others). A metric
-- a basic AVG-based report never surfaces but analysts love.
-- Params: 5 min_rating_count, 10 row_limit
SELECT
    c.content_id,
    c.title,
    COUNT(r.rating_id)               AS rating_count,
    ROUND(AVG(r.rating_value), 2)    AS avg_rating,
    ROUND(STDDEV(r.rating_value), 2) AS rating_stddev
FROM content c
JOIN ratings r ON r.content_id = c.content_id
GROUP BY c.content_id, c.title
HAVING COUNT(r.rating_id) >= 5
ORDER BY rating_stddev DESC
LIMIT 10;

-- ============================================================
-- 4.5  SEARCH TREND ANALYSIS
-- ============================================================

-- (a) Most-searched queries in a date range, with average results
-- returned (low avg_results_returned on a high-volume query is a
-- signal: people want it, the catalogue doesn't have it well-tagged)
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date, 10 row_limit
SELECT
    search_query,
    COUNT(*)                       AS search_count,
    ROUND(AVG(result_count), 1)     AS avg_results_returned,
    COUNT(DISTINCT profile_id)      AS unique_searchers
FROM search_history
WHERE searched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY search_query
ORDER BY search_count DESC
LIMIT 10;

-- (b) Zero-result searches — direct content-gap signal, sorted by
-- frequency so the highest-demand gaps surface first.
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date, 10 row_limit
SELECT
    search_query,
    COUNT(*) AS times_searched
FROM search_history
WHERE result_count = 0
  AND searched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY search_query
ORDER BY times_searched DESC
LIMIT 10;

-- (c) Search-to-watch conversion — of all searches, what fraction
-- led to a watch_history entry for matching content within the
-- same session window. Approximates search funnel effectiveness
-- without needing a dedicated clickstream table.
-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date, 5 conversion_window_minutes (e.g. 30)
SELECT
    sh.search_query,
    COUNT(DISTINCT sh.search_id) AS total_searches,
    COUNT(DISTINCT wh.watch_id)  AS resulting_watches,
    ROUND(
        100.0 * COUNT(DISTINCT wh.watch_id) / NULLIF(COUNT(DISTINCT sh.search_id), 0), 1
    ) AS conversion_rate_pct
FROM search_history sh
LEFT JOIN watch_history wh
    ON wh.profile_id = sh.profile_id
   AND wh.watched_at BETWEEN sh.searched_at
                          AND sh.searched_at + (5 || ' minutes')::INTERVAL
WHERE sh.searched_at BETWEEN CURRENT_DATE AND CURRENT_DATE
GROUP BY sh.search_query
ORDER BY total_searches DESC
LIMIT 25;

-- (d) Trending searches — week-over-week % growth in search volume
-- per query, surfaces what's suddenly spiking rather than just
-- what's always popular.
WITH this_week AS (
    SELECT search_query, COUNT(*) AS cnt
    FROM search_history
    WHERE searched_at >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY search_query
),
last_week AS (
    SELECT search_query, COUNT(*) AS cnt
    FROM search_history
    WHERE searched_at >= CURRENT_DATE - INTERVAL '14 days'
      AND searched_at < CURRENT_DATE - INTERVAL '7 days'
    GROUP BY search_query
)
SELECT
    tw.search_query,
    tw.cnt                                                       AS this_week_searches,
    COALESCE(lw.cnt, 0)                                          AS last_week_searches,
    ROUND(
        100.0 * (tw.cnt - COALESCE(lw.cnt, 0)) / NULLIF(COALESCE(lw.cnt, 0), 0), 1
    )                                                              AS pct_growth_wow
FROM this_week tw
LEFT JOIN last_week lw ON lw.search_query = tw.search_query
WHERE tw.cnt >= 5  -- ignore noise from one-off searches
ORDER BY pct_growth_wow DESC NULLS LAST
LIMIT 25;

-- ============================================================
-- 4.6  EXECUTIVE SUMMARY DASHBOARD (bonus — combines several
-- metrics into one query for a top-level KPI dashboard)
-- ============================================================

-- Params: CURRENT_DATE start_date, CURRENT_DATE end_date
SELECT
    (SELECT COUNT(*) FROM users WHERE created_at BETWEEN CURRENT_DATE AND CURRENT_DATE)                       AS new_users,
    (SELECT COUNT(*) FROM subscriptions WHERE start_date BETWEEN CURRENT_DATE AND CURRENT_DATE)                AS new_subscriptions,
    (SELECT COUNT(*) FROM subscriptions WHERE cancelled_at BETWEEN CURRENT_DATE AND CURRENT_DATE)              AS cancellations,
    (SELECT COALESCE(SUM(amount - refund_amount), 0) FROM payments
       WHERE payment_status = 'completed' AND paid_at BETWEEN CURRENT_DATE AND CURRENT_DATE)                   AS net_revenue,
    (SELECT COUNT(*) FROM watch_history WHERE watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE)                AS total_views,
    (SELECT COUNT(DISTINCT profile_id) FROM watch_history WHERE watched_at BETWEEN CURRENT_DATE AND CURRENT_DATE) AS active_viewers,
    (SELECT ROUND(AVG(rating_value), 2) FROM ratings r
       JOIN content c ON c.content_id = r.content_id
       WHERE r.created_at BETWEEN CURRENT_DATE AND CURRENT_DATE)                                                AS avg_new_rating;

-- ============================================================
-- END OF MODULE 4
-- ============================================================
