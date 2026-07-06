-- ============================================================
-- PROJECT  : Netflix-Type Streaming Platform
-- FILE     : netflix_queries_v2.sql
-- PURPOSE  : Finalized reference of all CRUD operations across
--            every domain in netflix_schema_v4.sql
-- DATABASE : PostgreSQL
-- USAGE    : Replace the literal example values (IDs, emails,
--            dates) with real ones from your application layer.
--            Every query below has been executed successfully,
--            in this exact order, against a live instance of
--            netflix_schema_v4.sql.
-- ============================================================


-- ============================================================
-- 1. USER MANAGEMENT
-- ============================================================

-- 1.1 CREATE a new user (signup)
INSERT INTO users (email, password_hash, full_name, phone_number, date_of_birth, country_code, account_status, email_verified)
VALUES ('jane.doe@example.com', '$2b$12$examplehashvalue', 'Jane Doe', '9876543210', '1998-03-22', 'IN', 'pending', FALSE)
RETURNING user_id, email, account_status;

-- 1.2 UPDATE user profile info (name, phone, avatar)
UPDATE users
SET full_name = 'Harapal S. Singh',
    phone_number = '9998887777',
    avatar_url = 'https://cdn.example.com/avatars/u1.png',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1;

-- 1.3 UPDATE / change password
UPDATE users
SET password_hash = '$2b$12$newhashedpasswordvalue',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1;

-- 1.4 VERIFY email (mark verified + auto-activate account)
UPDATE users
SET email_verified = TRUE,
    account_status = 'active',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 2 AND account_status = 'pending';

-- 1.5 DELETE a user
-- WARNING: ON DELETE CASCADE removes profiles; subscriptions/payments
-- use ON DELETE RESTRICT, so close those out first, or soft-delete via
-- account_status = 'suspended' instead in production.
-- (Demonstrated on a disposable throwaway user so this file can be
-- run start-to-finish without deleting IDs used by later sections.)
INSERT INTO users (email, password_hash, full_name, date_of_birth, country_code)
VALUES ('throwaway@example.com', 'x', 'Throwaway User', '2000-01-01', 'IN')
RETURNING user_id;

DELETE FROM users
WHERE email = 'throwaway@example.com';


-- ============================================================
-- 2. PROFILE MANAGEMENT
-- ============================================================

-- 2.1 CREATE a new profile
-- App-layer check first: COUNT(profiles) for user_id < plan's max_profiles
INSERT INTO profiles (user_id, profile_name, avatar_url, is_kids, is_primary)
VALUES (1, 'Guest', 'https://cdn.example.com/avatars/default3.png', FALSE, FALSE)
RETURNING profile_id, profile_name;

-- 2.2 CREATE the first (primary) profile for a new user
INSERT INTO profiles (user_id, profile_name, is_kids, is_primary)
VALUES (2, 'New User', FALSE, TRUE)
RETURNING profile_id;

-- 2.3 CHECK profile count against plan limit before creating a new one
SELECT
    (SELECT COUNT(*) FROM profiles WHERE user_id = 1) AS current_profiles,
    sp.max_profiles
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.user_id = 1 AND s.status = 'active';

-- 2.4 UPDATE profile (rename, change avatar, toggle kids mode)
UPDATE profiles
SET profile_name = 'Harapal Singh',
    avatar_url = 'https://cdn.example.com/avatars/u1p1.png',
    is_kids = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE profile_id = 1;

-- 2.5 SET a different profile as primary (two-step: clear old, set new)
UPDATE profiles SET is_primary = FALSE, updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1 AND is_primary = TRUE;

UPDATE profiles SET is_primary = TRUE, updated_at = CURRENT_TIMESTAMP
WHERE profile_id = 2;

-- 2.6 DELETE a profile (cascades to ratings, watch_history, my_list,
-- downloads, search_history, profile_preferences)
-- (Demonstrated on a disposable throwaway profile so this file can be
-- run start-to-finish without deleting IDs used by later sections.)
INSERT INTO profiles (user_id, profile_name, is_kids, is_primary)
VALUES (1, 'Throwaway Profile', FALSE, FALSE)
RETURNING profile_id;

DELETE FROM profiles
WHERE profile_name = 'Throwaway Profile' AND is_primary = FALSE;


-- ============================================================
-- 3. SUBSCRIPTION PLANS
-- ============================================================

-- 3.1 CREATE a new subscription plan (admin/catalog task)
INSERT INTO subscription_plans (plan_name, price_monthly, price_yearly, currency, max_screens, max_profiles, video_quality, hdr_support, dolby_atmos, max_downloads, ads_supported)
VALUES ('Standard', 11.99, 119.99, 'USD', 2, 4, 'Full HD', TRUE, FALSE, 25, FALSE)
RETURNING plan_id, plan_name;

-- 3.2 READ all active plans (pricing page)
SELECT plan_id, plan_name, price_monthly, price_yearly, currency,
       max_screens, max_profiles, video_quality, hdr_support, dolby_atmos, max_downloads, ads_supported
FROM subscription_plans
WHERE is_active = TRUE
ORDER BY price_monthly ASC;

-- 3.3 UPDATE plan pricing
UPDATE subscription_plans
SET price_monthly = 18.99,
    price_yearly = 189.99,
    updated_at = CURRENT_TIMESTAMP
WHERE plan_id = 2;

-- 3.4 DEACTIVATE a plan (soft-delete, keeps history intact)
UPDATE subscription_plans
SET is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE plan_id = 1;

-- 3.5 ADD / REMOVE an allowed device type on a plan
INSERT INTO plan_allowed_devices (plan_id, device_type)
VALUES (1, 'smart_tv')
ON CONFLICT (plan_id, device_type) DO NOTHING;

DELETE FROM plan_allowed_devices
WHERE plan_id = 1 AND device_type = 'smart_tv';


-- ============================================================
-- 4. SUBSCRIPTIONS
-- ============================================================

-- 4.1 CREATE a new subscription (user signs up for a plan)
-- (uses user_id 2 here since user_id 1 already holds an active
-- subscription — only one active subscription is allowed per user)
INSERT INTO subscriptions (user_id, plan_id, status, billing_cycle, start_date, next_billing_date, auto_renew)
VALUES (2, 1, 'active', 'monthly', CURRENT_DATE, CURRENT_DATE + INTERVAL '1 month', TRUE)
RETURNING subscription_id;

-- 4.2 READ the current active subscription for a user
SELECT s.subscription_id, sp.plan_name, s.status, s.billing_cycle,
       s.start_date, s.next_billing_date, s.auto_renew
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.user_id = 1 AND s.status = 'active';

-- 4.3 READ a user's full subscription history
SELECT s.subscription_id, sp.plan_name, s.status, s.start_date, s.end_date, s.cancellation_reason
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.user_id = 1
ORDER BY s.start_date DESC;

-- 4.4 UPGRADE / DOWNGRADE plan (end current, start new)
UPDATE subscriptions
SET status = 'expired',
    end_date = CURRENT_DATE,
    next_billing_date = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1 AND status = 'active';

INSERT INTO subscriptions (user_id, plan_id, status, billing_cycle, start_date, next_billing_date, auto_renew)
VALUES (1, 2, 'active', 'monthly', CURRENT_DATE, CURRENT_DATE + INTERVAL '1 month', TRUE)
RETURNING subscription_id;

-- 4.5 CANCEL a subscription (keeps access until end_date, stops renewal)
UPDATE subscriptions
SET status = 'cancelled',
    auto_renew = FALSE,
    cancelled_at = CURRENT_TIMESTAMP,
    cancellation_reason = 'Switching to a different service',
    next_billing_date = NULL,
    updated_at = CURRENT_TIMESTAMP
WHERE subscription_id = 2 AND status = 'active';

-- 4.6 PAUSE a subscription (temporary hold, e.g. billing dispute)
UPDATE subscriptions
SET status = 'paused',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1 AND status = 'active';

-- 4.7 RESUME a paused subscription
UPDATE subscriptions
SET status = 'active',
    next_billing_date = CURRENT_DATE + INTERVAL '1 month',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1 AND status = 'paused';

-- 4.8 RENEW subscription on billing date (advance next_billing_date)
UPDATE subscriptions
SET next_billing_date = next_billing_date + INTERVAL '1 month',
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = 1 AND status = 'active' AND auto_renew = TRUE;

-- 4.9 FIND subscriptions due for renewal today (billing job)
SELECT subscription_id, user_id, plan_id, billing_cycle
FROM subscriptions
WHERE status = 'active' AND auto_renew = TRUE AND next_billing_date = CURRENT_DATE;


-- ============================================================
-- 5. PAYMENTS
-- ============================================================

-- 5.1 CREATE / record a new payment (card)
INSERT INTO payments (subscription_id, user_id, amount, currency, payment_method, payment_status, transaction_id, gateway_name, card_last4, card_brand, invoice_url, paid_at)
VALUES (1, 1, 17.99, 'USD', 'credit_card', 'completed', 'txn_8823ab', 'stripe', '4242', 'visa', 'https://cdn.example.com/invoices/inv1.pdf', CURRENT_TIMESTAMP)
RETURNING payment_id;

-- 5.2 CREATE / record a new payment (UPI)
INSERT INTO payments (subscription_id, user_id, amount, currency, payment_method, payment_status, transaction_id, gateway_name, upi_id, upi_app, paid_at)
VALUES (1, 1, 17.99, 'USD', 'upi', 'completed', 'txn_upi_5521', 'razorpay', 'jane@upi', 'gpay', CURRENT_TIMESTAMP)
RETURNING payment_id;

-- 5.3 READ payment history for a user
SELECT payment_id, amount, currency, payment_method, payment_status, paid_at, invoice_url
FROM payments
WHERE user_id = 1
ORDER BY created_at DESC;

-- 5.4 READ a single payment's full detail
SELECT * FROM payments WHERE payment_id = 1;


-- ============================================================
-- 6. DEVICES
-- ============================================================

-- 6.1 REGISTER a new device
INSERT INTO user_devices (user_id, os_type, device_type, last_active_at)
VALUES (1, 'iOS', 'smartphone', CURRENT_TIMESTAMP)
RETURNING device_id;

-- 6.2 READ all devices for a user
SELECT device_id, os_type, device_type, last_active_at
FROM user_devices
WHERE user_id = 1
ORDER BY last_active_at DESC;

-- 6.3 UPDATE device last-active timestamp (ping on stream start)
UPDATE user_devices
SET last_active_at = CURRENT_TIMESTAMP
WHERE device_id = 1;

-- 6.4 REMOVE / deregister a device (cascades to downloads;
-- search_history.device_id is set NULL rather than deleted)
DELETE FROM user_devices
WHERE device_id = 2;


-- ============================================================
-- 7. CONTENT CATALOG
-- ============================================================

-- 7.1 CREATE a new Movie
INSERT INTO content (title, description, content_type, content_category, release_date, duration_minutes, poster_url, trailer_url, status)
VALUES ('Midnight Run', 'A high-stakes heist thriller', 'Movie', 'Netflix Original', '2026-09-01', 118, 'https://cdn.example.com/posters/mr.jpg', 'https://cdn.example.com/trailers/mr.mp4', 'ComingSoon')
RETURNING content_id;

-- 7.2 CREATE a new Series (no duration_minutes — lives on episodes)
INSERT INTO content (title, description, content_type, content_category, release_date, poster_url, status)
VALUES ('Northern Lights', 'A family drama across three generations', 'Series', 'Trending Now', '2026-10-15', 'https://cdn.example.com/posters/nl.jpg', 'ComingSoon')
RETURNING content_id;

-- 7.3 CREATE a season for a series
INSERT INTO seasons (content_id, season_number, title, description, release_date)
VALUES (2, 2, 'Season 2', 'The return', '2026-10-15')
RETURNING season_id;

-- 7.4 CREATE an episode within a season
INSERT INTO episodes (season_id, episode_number, title, description, duration_minutes, release_date, video_url, thumbnail_url)
VALUES (1, 3, 'Aftermath', 'The fallout continues', 44, '2023-01-24', 'https://cdn.example.com/video/cl-s1e3.mp4', 'https://cdn.example.com/thumb/cl-s1e3.jpg')
RETURNING episode_id;

-- 7.5 CREATE a new actor
INSERT INTO actors (actor_name, date_of_birth, gender, nationality, bio, photo_url)
VALUES ('Sofia Marchetti', '1992-11-03', 'Female', 'Italy', 'Award-winning stage and screen actor.', 'https://cdn.example.com/actors/sm.jpg')
RETURNING actor_id;

-- 7.6 ASSIGN an actor to content (cast)
INSERT INTO content_cast (content_id, actor_id, character_name, cast_order, is_main_cast)
VALUES (1, 1, 'Detective Marlow', 1, TRUE)
RETURNING cast_id;

-- 7.7 TAG content with a genre
INSERT INTO content_genres (content_id, genre_id)
VALUES (1, 3)
ON CONFLICT DO NOTHING;

-- 7.8 REMOVE a genre tag from content
DELETE FROM content_genres WHERE content_id = 1 AND genre_id = 2;

-- 7.9 ADD a language track to content
INSERT INTO content_languages (content_id, language_id, language_type, is_default)
VALUES (1, 3, 'Subtitle', FALSE)
RETURNING content_language_id;

-- 7.10 SET the default audio track for a title (add the new track, clear
-- the old default, then flip the new one on — in that order, so the
-- partial unique index never sees two defaults for the same type at once)
INSERT INTO content_languages (content_id, language_id, language_type, is_default)
VALUES (1, 2, 'Audio', FALSE);

UPDATE content_languages SET is_default = FALSE
WHERE content_id = 1 AND language_type = 'Audio';

UPDATE content_languages SET is_default = TRUE
WHERE content_id = 1 AND language_id = 2 AND language_type = 'Audio';

-- 7.11 SET country availability window for content
INSERT INTO content_availability (content_id, country_code, available_from, available_to, region_notes)
VALUES (1, 'GB', '2026-09-01', NULL, 'Day-and-date release')
RETURNING availability_id;

-- 7.12 END availability for a title in a country
UPDATE content_availability
SET available_to = CURRENT_DATE
WHERE content_id = 1 AND country_code = 'US' AND available_to IS NULL;

-- 7.13 PUBLISH content (ComingSoon -> Active)
UPDATE content
SET status = 'Active', updated_at = CURRENT_TIMESTAMP
WHERE content_id = 1 AND status = 'ComingSoon';

-- 7.14 RETIRE / deactivate content (soft-delete, preserves history)
UPDATE content
SET status = 'Inactive', updated_at = CURRENT_TIMESTAMP
WHERE content_id = 3;

-- 7.15 DELETE content entirely (cascades to seasons, episodes, cast,
-- genre tags, language tracks, availability, ratings, watch_history,
-- my_list, downloads — use status = 'Inactive' instead in production)
INSERT INTO content (title, content_type, status)
VALUES ('Throwaway Title', 'Movie', 'Inactive')
RETURNING content_id;

DELETE FROM content WHERE title = 'Throwaway Title';

-- 7.16 SEARCH content by title (catalog search)
SELECT content_id, title, content_type, content_category, release_date, poster_url
FROM content
WHERE status = 'Active' AND title ILIKE '%light%'
ORDER BY release_date DESC;

-- 7.17 FILTER content by genre
SELECT c.content_id, c.title, c.content_type, c.release_date
FROM content c
JOIN content_genres cg ON cg.content_id = c.content_id
JOIN genres g ON g.genre_id = cg.genre_id
WHERE g.genre_name = 'Drama' AND c.status = 'Active'
ORDER BY c.release_date DESC;

-- 7.18 GET full content detail page (genres, cast, language tracks, availability)
SELECT c.content_id, c.title, c.description, c.content_type, c.content_category,
       c.release_date, c.duration_minutes, c.poster_url, c.trailer_url,
       ARRAY_AGG(DISTINCT g.genre_name) AS genres
FROM content c
LEFT JOIN content_genres cg ON cg.content_id = c.content_id
LEFT JOIN genres g ON g.genre_id = cg.genre_id
WHERE c.content_id = 2
GROUP BY c.content_id;

-- 7.19 GET cast list for a title, ordered by billing
SELECT a.actor_name, cc.character_name, cc.cast_order, cc.is_main_cast
FROM content_cast cc
JOIN actors a ON a.actor_id = cc.actor_id
WHERE cc.content_id = 2
ORDER BY cc.cast_order ASC;


-- ============================================================
-- 8. WATCH HISTORY
-- ============================================================

-- 8.1 LOG a new watch session (movie)
INSERT INTO watch_history (profile_id, content_id, watch_duration_seconds, progress_seconds, completed)
VALUES (1, 2, 600, 600, FALSE)
RETURNING watch_id;

-- 8.2 LOG a watch session for a specific episode
INSERT INTO watch_history (profile_id, content_id, episode_id, watch_duration_seconds, progress_seconds, completed)
VALUES (1, 2, 2, 1500, 2520, TRUE)
RETURNING watch_id;

-- 8.3 UPDATE progress on an in-progress watch (resume tracking)
UPDATE watch_history
SET progress_seconds = 2100,
    watch_duration_seconds = watch_duration_seconds + 300
WHERE watch_id = 1;

-- 8.4 MARK a watch session as completed
UPDATE watch_history
SET completed = TRUE
WHERE watch_id = 1;

-- 8.5 GET "Continue Watching" row for a profile (most recent unfinished per title)
SELECT DISTINCT ON (wh.content_id)
       wh.content_id, c.title, wh.episode_id, wh.progress_seconds, wh.watched_at
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
WHERE wh.profile_id = 1 AND wh.completed = FALSE
ORDER BY wh.content_id, wh.watched_at DESC;

-- 8.6 GET full watch history for a profile (most recent 8)
SELECT wh.watch_id, c.title, wh.episode_id, wh.watched_at, wh.progress_seconds, wh.completed
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
WHERE wh.profile_id = 1
ORDER BY wh.watched_at DESC
LIMIT 8;

-- 8.7 CLEAR watch history for a profile
DELETE FROM watch_history WHERE profile_id = 1;

-- 8.8 DELETE a single watch history entry
DELETE FROM watch_history WHERE watch_id = 2;


-- ============================================================
-- 9. RATINGS & REVIEWS
-- ============================================================

-- 9.1 CREATE or UPDATE a rating (upsert — one rating per profile/title)
INSERT INTO ratings (profile_id, content_id, is_liked, review_text)
VALUES (1, 2, TRUE, 'Gripping from the first episode.')
ON CONFLICT (profile_id, content_id)
DO UPDATE SET is_liked = EXCLUDED.is_liked,
              review_text = EXCLUDED.review_text,
              updated_at = CURRENT_TIMESTAMP
RETURNING rating_id;

-- 9.2 READ all reviews for a title
SELECT r.review_text, r.is_liked, r.created_at, p.profile_name
FROM ratings r
JOIN profiles p ON p.profile_id = r.profile_id
WHERE r.content_id = 2 AND r.review_text IS NOT NULL
ORDER BY r.created_at DESC;


-- ============================================================
-- 10. MY LIST (watchlist)
-- ============================================================

-- 10.1 ADD a title to My List
INSERT INTO my_list (profile_id, content_id)
VALUES (1, 2)
ON CONFLICT (profile_id, content_id) DO NOTHING
RETURNING my_list_id;

-- 10.2 READ a profile's My List
SELECT ml.my_list_id, c.content_id, c.title, c.poster_url, ml.added_at
FROM my_list ml
JOIN content c ON c.content_id = ml.content_id
WHERE ml.profile_id = 1
ORDER BY ml.added_at DESC;

-- 10.3 CHECK if a title is already in a profile's My List (toggle button state)
SELECT EXISTS (
    SELECT 1 FROM my_list WHERE profile_id = 1 AND content_id = 2
) AS in_my_list;

-- 10.4 REMOVE a title from My List
DELETE FROM my_list WHERE profile_id = 1 AND content_id = 2;


-- ============================================================
-- 11. DOWNLOADS
-- ============================================================

-- 11.1 CREATE a new download
INSERT INTO downloads (profile_id, content_id, episode_id, device_id, expiry_date, file_size_mb, download_status)
VALUES (1, 2, 2, 1, CURRENT_DATE + INTERVAL '30 days', 380.2, 'Active')
RETURNING download_id;

-- 11.2 READ active downloads on a specific device
SELECT d.download_id, c.title, d.episode_id, d.file_size_mb, d.expiry_date
FROM downloads d
JOIN content c ON c.content_id = d.content_id
WHERE d.profile_id = 1 AND d.device_id = 1 AND d.download_status = 'Active'
ORDER BY d.downloaded_at DESC;

-- 11.3 DELETE / remove a download manually (user frees up space)
DELETE FROM downloads WHERE download_id = 1;


-- ============================================================
-- 12. SEARCH HISTORY
-- ============================================================

-- 12.1 LOG a search query
INSERT INTO search_history (profile_id, search_query, result_count, device_id)
VALUES (1, 'northern lights', 1, 1)
RETURNING search_id;

-- 12.2 READ recent searches for a profile (most recent 8)
SELECT search_query, searched_at, result_count
FROM search_history
WHERE profile_id = 1
ORDER BY searched_at DESC
LIMIT 8;

-- 12.3 CLEAR all search history for a profile
DELETE FROM search_history WHERE profile_id = 1;

-- 12.4 DELETE a single search history entry
INSERT INTO search_history (profile_id, search_query, result_count, device_id)
VALUES (1, 'temp query for delete demo', 0, 1)
RETURNING search_id;

DELETE FROM search_history WHERE search_query = 'temp query for delete demo';


-- ============================================================
-- 13. PROFILE PREFERENCES
-- ============================================================

-- 13.1 CREATE default preferences for a new profile (call right after profile creation)
INSERT INTO profile_preferences (profile_id, audio_language, default_quality, ui_theme, language)
VALUES (2, 'en', 'auto', 'dark', 'en')
ON CONFLICT (profile_id) DO NOTHING
RETURNING preference_id;

-- 13.2 READ / UPDATE a profile's preferences

-- Read
SELECT audio_language, default_quality, notifications_on, new_releases_notif,
       continue_watching, ui_theme, language, autoplay_next, autoplay_previews
FROM profile_preferences
WHERE profile_id = 1;

-- Update (upsert — safe to call even if the row doesn't exist yet)
INSERT INTO profile_preferences (profile_id, audio_language, default_quality, ui_theme, language, autoplay_next, autoplay_previews)
VALUES (1, 'hi', 'ultra', 'light', 'hi', FALSE, TRUE)
ON CONFLICT (profile_id)
DO UPDATE SET audio_language = EXCLUDED.audio_language,
              default_quality = EXCLUDED.default_quality,
              ui_theme = EXCLUDED.ui_theme,
              language = EXCLUDED.language,
              autoplay_next = EXCLUDED.autoplay_next,
              autoplay_previews = EXCLUDED.autoplay_previews,
              updated_at = CURRENT_TIMESTAMP;
