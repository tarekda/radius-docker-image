-- patch_quota_cycle.sql: single source of truth for the monthly quota window.
--
-- Applied idempotently on every container start by bootstrap_schema.sh.
--
-- Fixes:
-- 1) quota_reset_day >= 29 produced an invalid date (e.g. Feb 31 -> NULL) in the
--    inline window SQL, silently disabling monthly enforcement in short months.
--    The function clamps the reset day to the month length (same as the backend's
--    computeMonthlyCycleDates / frontend quotaCycle.ts).
-- 2) reset_monthly_quotas() only ran on day 1 of the month, so users with a
--    mid-month quota_reset_day stayed on the Fallback profile until the next 1st.
--    It now restores each user on *their* cycle boundary.
-- 3) remaining_quota view used its own (unclamped, anchor-unaware) window and
--    could disagree with what RADIUS actually enforces.

USE radius;

DROP FUNCTION IF EXISTS fn_quota_cycle_start;

DELIMITER //

-- Start date of the user's current monthly quota window.
-- - quota_cycle_start_date (manual anchor, refreshed by the backend on renewal) wins when set.
-- - Otherwise: most recent occurrence of quota_reset_day, clamped to the month length.
CREATE FUNCTION fn_quota_cycle_start(p_username VARCHAR(64))
RETURNS DATE
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_anchor DATE DEFAULT NULL;
    DECLARE v_reset_day INT DEFAULT 1;
    DECLARE v_candidate DATE;
    DECLARE v_prev_first DATE;

    SELECT quota_cycle_start_date, COALESCE(quota_reset_day, 1)
      INTO v_anchor, v_reset_day
      FROM raduserprofile
     WHERE username = p_username
     LIMIT 1;

    IF v_anchor IS NOT NULL THEN
        RETURN v_anchor;
    END IF;

    -- This month's reset date, clamped (e.g. day 31 -> Feb 28).
    SET v_candidate = DATE_ADD(
        DATE_FORMAT(CURDATE(), '%Y-%m-01'),
        INTERVAL LEAST(v_reset_day, DAY(LAST_DAY(CURDATE()))) - 1 DAY
    );
    IF v_candidate <= CURDATE() THEN
        RETURN v_candidate;
    END IF;

    -- Reset day hasn't happened yet this month: use last month's (clamped).
    SET v_prev_first = DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 1 MONTH), '%Y-%m-01');
    RETURN DATE_ADD(
        v_prev_first,
        INTERVAL LEAST(v_reset_day, DAY(LAST_DAY(v_prev_first))) - 1 DAY
    );
END //

DELIMITER ;

DROP PROCEDURE IF EXISTS reset_monthly_quotas;

DELIMITER //

-- Restore users whose monthly cycle restarts TODAY (per-user reset day / anchor),
-- not globally on day 1. Runs daily (event + reset_daily_quota_all.sh).
CREATE PROCEDURE reset_monthly_quotas()
BEGIN
    -- Materialize the user set first: MySQL forbids calling a function that reads
    -- raduserprofile from within an UPDATE of raduserprofile (error 1442).
    DROP TEMPORARY TABLE IF EXISTS tmp_monthly_resets;
    CREATE TEMPORARY TABLE tmp_monthly_resets AS
      SELECT username FROM raduserprofile
      WHERE COALESCE(is_monthly_exceeded, 0) = 1
        AND fn_quota_cycle_start(username) = CURDATE();

    -- NOTE: quota_logs has no `details` column (the old proc referenced one and
    -- failed silently at runtime). Keep the insert aligned with the live schema.
    INSERT INTO quota_logs (username, event_type, quota_type, timestamp)
    SELECT username, 'reset', 'monthly', NOW()
    FROM tmp_monthly_resets;

    UPDATE raduserprofile up
    JOIN tmp_monthly_resets t
      ON BINARY t.username = BINARY up.username
    LEFT JOIN user_default_profiles udp
      ON BINARY udp.username = BINARY up.username
    SET up.is_monthly_exceeded = 0,
        up.is_fallback = 0,
        up.profile_id = COALESCE(udp.default_profile_id, up.profile_id);

    DROP TEMPORARY TABLE IF EXISTS tmp_monthly_resets;
END //

DELIMITER ;

-- Align the monitoring view with actual enforcement (same window function).
-- Column names kept for compatibility; last_reset_date = current cycle start.
-- Aggregates (MAX) keep the view valid under only_full_group_by (MySQL 8 default).
CREATE OR REPLACE VIEW remaining_quota AS
SELECT
    u.username,
    MAX(COALESCE(p_default.monthly_quota, p.monthly_quota)) AS total_quota,
    MAX(COALESCE(p_default.monthly_quota, p.monthly_quota)) - COALESCE(SUM(s.data_usage), 0) AS remaining_quota,
    MAX(u.quota_reset_day) AS reset_day,
    MAX(CASE
        WHEN u.is_monthly_exceeded = 1 THEN 'Exceeded'
        ELSE u.account_status
    END) AS quota_status,
    MAX(fn_quota_cycle_start(u.username)) AS last_reset_date,
    DATE_ADD(MAX(fn_quota_cycle_start(u.username)), INTERVAL 1 MONTH) AS next_reset_date
FROM raduserprofile u
JOIN radprofile p ON u.profile_id = p.id
LEFT JOIN user_default_profiles udp ON BINARY udp.username = BINARY u.username
LEFT JOIN radprofile p_default ON p_default.id = udp.default_profile_id
LEFT JOIN radusagestats s
    ON s.username = u.username
   AND s.day >= fn_quota_cycle_start(u.username)
GROUP BY u.username;
