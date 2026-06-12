-- First, make sure we're using the correct database
USE radius;

-- Set delimiter for procedures
DELIMITER //

-- Procedure to reset monthly quotas
CREATE PROCEDURE reset_monthly_quotas()
proc: BEGIN
    DECLARE current_day INT;
    SET current_day = DAY(NOW());

    -- Global monthly reset: only run on the 1st day of the month (00:00).
    IF current_day <> 1 THEN
        LEAVE proc;
    END IF;
    
    -- Reset quotas for all users who were monthly-exceeded
    UPDATE raduserprofile
    SET is_monthly_exceeded = 0,
        is_fallback = 0,
        profile_id = (
            SELECT default_profile_id 
            FROM user_default_profiles 
            WHERE user_default_profiles.username = raduserprofile.username
        )
    WHERE is_monthly_exceeded = 1;
    
    -- Log reset events
    INSERT INTO quota_logs (username, event_type, quota_type, timestamp, details)
    SELECT username, 'reset', 'monthly', NOW(), 
           CONCAT('Monthly quota reset on day ', current_day)
    FROM raduserprofile
    WHERE is_monthly_exceeded = 0;
END //

-- Procedure to kill active sessions
CREATE PROCEDURE kill_session(IN p_username VARCHAR(64))
BEGIN
    UPDATE session_tracking 
    SET status = 'terminated', 
        end_time = NOW() 
    WHERE username = p_username 
    AND status = 'active';
END //

CREATE PROCEDURE sp_get_online_users()
BEGIN
    SELECT 
        ra.username,
        ra.framedipaddress as ip_address,
        ra.callingstationid as mac_address,
        ra.acctstarttime as start_time,
        TIMEDIFF(NOW(), ra.acctstarttime) as duration,
        ROUND(ra.acctinputoctets/1048576, 2) as download_mb,
        ROUND(ra.acctoutputoctets/1048576, 2) as upload_mb,
        up.account_status,
        p.profile_name
    FROM radacct ra
    JOIN raduserprofile up ON ra.username = up.username
    JOIN radprofile p ON up.profile_id = p.id
    WHERE ra.acctstoptime IS NULL
    ORDER BY ra.acctstarttime DESC;
END //

DELIMITER ;

-- Create events
CREATE EVENT reset_monthly_quotas_event
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_DATE + INTERVAL 1 DAY
DO
    CALL reset_monthly_quotas();

CREATE EVENT check_stale_sessions_daily
ON SCHEDULE EVERY 1 DAY
STARTS (DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 1 SECOND)
DO
    UPDATE session_tracking 
    SET status = 'completed', 
        end_time = NOW() 
    WHERE status = 'active';

CREATE EVENT delete_old_active_sessions
ON SCHEDULE EVERY 1 DAY
STARTS (DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 1 SECOND)
DO
  DELETE st
  FROM session_tracking st
  INNER JOIN (
      SELECT username, MAX(id) AS latest_id
      FROM session_tracking
      WHERE status = 'active'
      GROUP BY username
  ) latest ON st.username = latest.username
  WHERE st.status = 'active'
    AND st.id <> latest.latest_id;



-- Create views for monitoring
CREATE OR REPLACE VIEW session_stats AS
SELECT 
    username,
    COUNT(CASE WHEN status = 'active' THEN 1 END) as active_sessions,
    SUM(bytes_in) as total_bytes_in,
    SUM(bytes_out) as total_bytes_out,
    AVG(session_time) as avg_session_time
FROM session_tracking
GROUP BY username;

-- Add new view for remaining quota
CREATE OR REPLACE VIEW remaining_quota AS
SELECT 
    u.username,
    -- Always show quotas based on the user's default/original profile when available,
    -- not the current profile (which may be "Fallback").
    COALESCE(p_default.monthly_quota, p.monthly_quota) as total_quota,
    COALESCE(p_default.monthly_quota, p.monthly_quota) - COALESCE(SUM(s.data_usage), 0) as remaining_quota,
    u.quota_reset_day as reset_day,
    CASE 
        WHEN u.is_monthly_exceeded = 1 THEN 'Exceeded'
        ELSE u.account_status
    END as quota_status,
    DATE_FORMAT(NOW(), CONCAT('%Y-%m-', LPAD(u.quota_reset_day, 2, '0'))) as last_reset_date,
    DATE_FORMAT(DATE_ADD(NOW(), INTERVAL 1 MONTH), CONCAT('%Y-%m-', LPAD(u.quota_reset_day, 2, '0'))) as next_reset_date
FROM raduserprofile u
JOIN radprofile p ON u.profile_id = p.id
LEFT JOIN user_default_profiles udp ON BINARY udp.username = BINARY u.username
LEFT JOIN radprofile p_default ON p_default.id = udp.default_profile_id
LEFT JOIN radusagestats s ON u.username = s.username
    AND s.day >= DATE_FORMAT(NOW(), 
        CONCAT('%Y-%m-', LPAD(u.quota_reset_day, 2, '0')))
GROUP BY u.username; 

-- Add view for online users
CREATE OR REPLACE VIEW online_users AS
SELECT 
    ra.username,
    ra.framedipaddress as ip_address,
    ra.callingstationid as mac_address,
    ra.acctstarttime as start_time,
    ra.acctinterval as session_time,
    ROUND(ra.acctinputoctets/1048576, 2) as download_mb,
    ROUND(ra.acctoutputoctets/1048576, 2) as upload_mb,
    ra.nasipaddress as nas_ip
FROM radacct ra
WHERE ra.acctstoptime IS NULL;

DELIMITER //

CREATE PROCEDURE sp_handle_daily_quota_exceeded(
    IN p_username VARCHAR(64)
)
proc: BEGIN
    DECLARE v_profile_id INT;
    DECLARE v_daily_quota BIGINT;
    DECLARE v_data_usage BIGINT;
    DECLARE v_fallback_profile_id INT;
    DECLARE v_is_fallback TINYINT DEFAULT 0;

    -- Get the user's current profile and the daily quota from the *default/original* profile.
    -- IMPORTANT: when a user is already on the "Fallback" profile, we must NOT start
    -- comparing usage against the fallback quotas, otherwise users can get "stuck" in FUP.
    SELECT
        rup.profile_id,
        COALESCE(rp_default.daily_quota, rp_current.daily_quota),
        COALESCE(rup.is_fallback, 0)
    INTO v_profile_id, v_daily_quota, v_is_fallback
    FROM raduserprofile rup
    JOIN radprofile rp_current ON rup.profile_id = rp_current.id
    LEFT JOIN user_default_profiles udp ON BINARY udp.username = BINARY rup.username
    LEFT JOIN radprofile rp_default ON rp_default.id = udp.default_profile_id
    WHERE rup.username = p_username;

    -- Already in daily FUP; skip redundant updates/logs.
    IF v_is_fallback = 1 THEN
        LEAVE proc;
    END IF;

    SELECT id INTO v_fallback_profile_id
    FROM radprofile
    WHERE profile_name = 'Fallback'
    LIMIT 1;

    -- Get the user's data usage for today
    SELECT COALESCE(SUM(data_usage), 0)
    INTO v_data_usage
    FROM radusagestats
    WHERE username = p_username AND day = CURDATE();

    -- Check if the daily quota is exceeded
    IF v_data_usage >= v_daily_quota THEN
        -- Save the user's normal profile for later restore (avoid overwriting with fallback)
        IF v_profile_id IS NOT NULL AND (v_fallback_profile_id IS NULL OR v_profile_id <> v_fallback_profile_id) THEN
            INSERT INTO user_default_profiles (username, default_profile_id)
            VALUES (p_username, v_profile_id)
            ON DUPLICATE KEY UPDATE default_profile_id = VALUES(default_profile_id);
        END IF;

        -- Switch to fallback + mark daily FUP flag
        UPDATE raduserprofile
        SET profile_id = v_fallback_profile_id,
            is_fallback = 1
        WHERE username = p_username
          AND COALESCE(is_fallback, 0) = 0;

        -- Log only when we actually transitioned (avoids duplicate rows under concurrency).
        IF ROW_COUNT() > 0 THEN
            INSERT INTO quota_logs (username, event_type, quota_type, timestamp) 
            VALUES (p_username, 'exceeded', 'daily', NOW());
        END IF;
    END IF;
END //

DELIMITER ;


-- NOTE:
-- We intentionally do NOT create a "reset_daily_usage" event.
-- Daily usage should be accumulated from accounting Interim-Update/Stop deltas
-- into `radusagestats` (see `raddb/sites-available/default`).
-- The old midnight reset logic would double-count and/or miscount sessions
-- (especially sessions spanning midnight).

DELIMITER ;
