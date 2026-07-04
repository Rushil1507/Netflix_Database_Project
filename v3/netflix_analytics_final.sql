-- ============================================================
-- PROJECT  : Netflix-Type Streaming Platform
-- FILE     : netflix_analytics_final.sql
-- PURPOSE  : Final shortlisted Analytics & Business Reporting
--            queries, matched against netflix_schema_v5.sql
-- DATABASE : PostgreSQL
-- USAGE    : Every query below has been executed successfully
--            against a live instance of netflix_schema_v5.sql.
--            These are read-only (SELECT) queries — safe to run
--            in any order, independently of one another.
-- NOTE     : Numbering below intentionally matches the master
--            shortlist (some items were combined/dropped), so
--            numbers are not fully sequential.
-- ============================================================


-- 1. TOP 10 most-watched titles (by number of watch sessions)
SELECT c.content_id, c.title, COUNT(*) AS view_count
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
GROUP BY c.content_id, c.title
ORDER BY view_count DESC
LIMIT 10;


-- 2. MOST POPULAR genres by total watch time
SELECT g.genre_name, ROUND(SUM(wh.watch_duration_seconds) / 3600.0, 2) AS total_hours_watched
FROM watch_history wh
JOIN content_genres cg ON cg.content_id = wh.content_id
JOIN genres g ON g.genre_id = cg.genre_id
GROUP BY g.genre_name
ORDER BY total_hours_watched DESC;


-- 3. MONTHLY RECURRING REVENUE (MRR) by plan
SELECT sp.plan_name,
       COUNT(*) AS active_subscribers,
       COUNT(*) * sp.price_monthly AS mrr
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.status = 'active' AND s.billing_cycle = 'monthly'
GROUP BY sp.plan_name, sp.price_monthly
ORDER BY mrr DESC;


-- 4. TOTAL MRR across all plans, and ANNUAL RECURRING REVENUE (ARR) by plan

-- Total MRR (single dashboard number)
SELECT SUM(sp.price_monthly) AS total_mrr
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.status = 'active' AND s.billing_cycle = 'monthly';

-- ARR by plan (yearly-billed subscribers use price_yearly directly;
-- monthly-billed subscribers are annualized at price_monthly * 12)
SELECT sp.plan_name,
       SUM(
           CASE WHEN s.billing_cycle = 'yearly' THEN sp.price_yearly
                ELSE sp.price_monthly * 12
           END
       ) AS arr
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.status = 'active'
GROUP BY sp.plan_name
ORDER BY arr DESC;


-- 6. CHURNED users and CHURN RATE (%) for the last 30 days

-- Churned users count
SELECT COUNT(DISTINCT user_id) AS churned_users
FROM subscriptions
WHERE status = 'cancelled' AND cancelled_at >= CURRENT_DATE - INTERVAL '30 days';

-- Churn rate %
SELECT
    (SELECT COUNT(DISTINCT user_id) FROM subscriptions
     WHERE status = 'cancelled' AND cancelled_at >= CURRENT_DATE - INTERVAL '30 days') AS churned,
    (SELECT COUNT(DISTINCT user_id) FROM subscriptions
     WHERE start_date <= CURRENT_DATE - INTERVAL '30 days') AS base,
    ROUND(
      100.0 *
      (SELECT COUNT(DISTINCT user_id) FROM subscriptions
       WHERE status = 'cancelled' AND cancelled_at >= CURRENT_DATE - INTERVAL '30 days')
      / NULLIF((SELECT COUNT(DISTINCT user_id) FROM subscriptions
                WHERE start_date <= CURRENT_DATE - INTERVAL '30 days'), 0)
    , 2) AS churn_rate_pct;


-- 11. AVERAGE watch completion rate per title
SELECT c.title,
       ROUND(AVG(CASE WHEN wh.completed THEN 1 ELSE 0 END) * 100, 1) AS completion_rate_pct,
       COUNT(*) AS total_sessions
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
GROUP BY c.title
ORDER BY completion_rate_pct DESC;


-- 12. CONTENT with zero views (dead catalog / promotion candidates)
SELECT c.content_id, c.title, c.release_date
FROM content c
LEFT JOIN watch_history wh ON wh.content_id = c.content_id
WHERE c.status = 'Active' AND wh.watch_id IS NULL;


-- 13. TOP-RATED content by like percentage
-- (uses whole-title ratings only — season_id/episode_id/part_id all NULL —
-- so a title's score isn't skewed by however many episodes/parts it has)
SELECT c.title,
       COUNT(*) AS total_ratings,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.is_liked) / COUNT(*), 1) AS like_pct
FROM ratings r
JOIN content c ON c.content_id = r.content_id
WHERE r.season_id IS NULL AND r.episode_id IS NULL AND r.part_id IS NULL
GROUP BY c.title
HAVING COUNT(*) >= 1
ORDER BY like_pct DESC, total_ratings DESC;


-- 14. MOST-DISLIKED content by like percentage
-- (same whole-title basis as query 13, sorted the opposite way)
SELECT c.title,
       COUNT(*) AS total_ratings,
       ROUND(100.0 * COUNT(*) FILTER (WHERE r.is_liked) / COUNT(*), 1) AS like_pct
FROM ratings r
JOIN content c ON c.content_id = r.content_id
WHERE r.season_id IS NULL AND r.episode_id IS NULL AND r.part_id IS NULL
GROUP BY c.title
HAVING COUNT(*) >= 1
ORDER BY like_pct ASC, total_ratings DESC;


-- 15. DEVICE TYPE distribution across all registered devices
SELECT device_type, COUNT(*) AS device_count
FROM user_devices
GROUP BY device_type
ORDER BY device_count DESC;


-- 16. OPERATING SYSTEM distribution across all registered devices
SELECT os_type, COUNT(*) AS device_count
FROM user_devices
WHERE os_type IS NOT NULL
GROUP BY os_type
ORDER BY device_count DESC;


-- 17. REVENUE by payment method
SELECT payment_method, SUM(amount) AS total_amount, COUNT(*) AS transaction_count
FROM payments
WHERE payment_status = 'completed'
GROUP BY payment_method
ORDER BY total_amount DESC;


-- 21. SUBSCRIPTION PLAN DISTRIBUTION (active subscribers per plan)
SELECT sp.plan_name, COUNT(*) AS active_subscribers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_active_base
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
WHERE s.status = 'active'
GROUP BY sp.plan_name
ORDER BY active_subscribers DESC;


-- 22. SUBSCRIPTION STATUS BREAKDOWN (active/paused/cancelled/expired counts)
SELECT status, COUNT(*) AS subscription_count
FROM subscriptions
GROUP BY status
ORDER BY subscription_count DESC;


-- 23. USERS at their plan's profile limit (upsell candidates)
SELECT s.user_id, sp.plan_name, COUNT(p.profile_id) AS profile_count, sp.max_profiles
FROM subscriptions s
JOIN subscription_plans sp ON sp.plan_id = s.plan_id
JOIN profiles p ON p.user_id = s.user_id
WHERE s.status = 'active'
GROUP BY s.user_id, sp.plan_name, sp.max_profiles
HAVING COUNT(p.profile_id) >= sp.max_profiles;


-- 25. NEW SIGNUPS per month (last 12 months)
SELECT DATE_TRUNC('month', created_at)::DATE AS signup_month, COUNT(*) AS new_users
FROM users
WHERE created_at >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY signup_month;


-- 27. TOP SEARCH QUERIES overall
SELECT search_query, COUNT(*) AS times_searched
FROM search_history
GROUP BY search_query
ORDER BY times_searched DESC
LIMIT 20;


-- 28. CONTENT AVAILABILITY count by country (catalog breadth)
SELECT country_code, COUNT(DISTINCT content_id) AS titles_available
FROM content_availability
WHERE CURRENT_DATE >= available_from AND (available_to IS NULL OR CURRENT_DATE <= available_to)
GROUP BY country_code
ORDER BY titles_available DESC;


-- 29. CONTENT COUNT by genre
SELECT g.genre_name, COUNT(cg.content_id) AS title_count
FROM genres g
LEFT JOIN content_genres cg ON cg.genre_id = g.genre_id
GROUP BY g.genre_name
ORDER BY title_count DESC;


-- 31. CONTENT COUNT by category (Original, Trending, etc.)
SELECT COALESCE(content_category, 'Uncategorized') AS content_category, COUNT(*) AS title_count
FROM content
GROUP BY content_category
ORDER BY title_count DESC;


-- 32. DOWNLOAD ADOPTION RATE (% of profiles that have downloaded content)
SELECT
    (SELECT COUNT(DISTINCT profile_id) FROM downloads) AS profiles_with_downloads,
    (SELECT COUNT(*) FROM profiles) AS total_profiles,
    ROUND(
      100.0 * (SELECT COUNT(DISTINCT profile_id) FROM downloads)
      / NULLIF((SELECT COUNT(*) FROM profiles), 0)
    , 1) AS adoption_pct;


-- 35. CONTENT PERFORMANCE BY CATEGORY (watch time per content_category)
SELECT c.content_category, ROUND(SUM(wh.watch_duration_seconds) / 3600.0, 2) AS total_hours_watched,
       COUNT(DISTINCT c.content_id) AS titles_in_category
FROM watch_history wh
JOIN content c ON c.content_id = wh.content_id
WHERE c.content_category IS NOT NULL
GROUP BY c.content_category
ORDER BY total_hours_watched DESC;


-- 40. FAILED PAYMENT count and value (last 30 days)
SELECT COUNT(*) AS failed_payment_count, SUM(amount) AS failed_payment_value
FROM payments
WHERE payment_status = 'failed' AND created_at >= CURRENT_DATE - INTERVAL '30 days';


-- 41. AUTO-RENEW OPT-OUT RATE (% of active subscriptions with auto_renew = false)
SELECT
    COUNT(*) FILTER (WHERE auto_renew = FALSE) AS opted_out,
    COUNT(*) AS total_active,
    ROUND(100.0 * COUNT(*) FILTER (WHERE auto_renew = FALSE) / NULLIF(COUNT(*), 0), 1) AS opt_out_rate_pct
FROM subscriptions
WHERE status = 'active';


-- 42. MOST-WATCHED genre PER PROFILE (personalization signal)
SELECT DISTINCT ON (wh.profile_id)
       wh.profile_id, g.genre_name, SUM(wh.watch_duration_seconds) AS total_seconds
FROM watch_history wh
JOIN content_genres cg ON cg.content_id = wh.content_id
JOIN genres g ON g.genre_id = cg.genre_id
GROUP BY wh.profile_id, g.genre_name
ORDER BY wh.profile_id, total_seconds DESC;


-- 43. CONTENT ADDED TO MY LIST but never watched (conversion gap)
SELECT p.profile_id, c.title, ml.added_at
FROM my_list ml
JOIN profiles p ON p.profile_id = ml.profile_id
JOIN content c ON c.content_id = ml.content_id
LEFT JOIN watch_history wh ON wh.profile_id = ml.profile_id AND wh.content_id = ml.content_id
WHERE wh.watch_id IS NULL
ORDER BY ml.added_at DESC;


-- 44. AVERAGE PROFILES PER USER ACCOUNT
SELECT ROUND(
         (SELECT COUNT(*) FROM profiles)::NUMERIC
         / NULLIF((SELECT COUNT(*) FROM users), 0)
       , 2) AS avg_profiles_per_user;


-- 45. AVERAGE DEVICES PER USER ACCOUNT
SELECT ROUND(
         (SELECT COUNT(*) FROM user_devices)::NUMERIC
         / NULLIF((SELECT COUNT(*) FROM users), 0)
       , 2) AS avg_devices_per_user;


-- 46. CAST/ACTOR with the most titles in the catalog
SELECT a.actor_id, a.actor_name, COUNT(DISTINCT cc.content_id) AS title_count
FROM actors a
JOIN content_cast cc ON cc.actor_id = a.actor_id
GROUP BY a.actor_id, a.actor_name
ORDER BY title_count DESC
LIMIT 10;


-- 47. CONTENT RELEASED per month (catalog growth over time)
SELECT DATE_TRUNC('month', release_date)::DATE AS release_month, COUNT(*) AS titles_released
FROM content
WHERE release_date IS NOT NULL
GROUP BY DATE_TRUNC('month', release_date)
ORDER BY release_month;
