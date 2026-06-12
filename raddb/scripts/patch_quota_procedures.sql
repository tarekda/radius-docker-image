-- Idempotent quota-exceeded procedures (applied on existing DBs via bootstrap_schema.sh).
-- Prevents duplicate quota_logs rows when accounting Stop + Interim-Update both fire,
-- or when procedures are called more than once while the user is already in FUP.

USE radius;

DROP PROCEDURE IF EXISTS sp_handle_daily_quota_exceeded;
DROP PROCEDURE IF EXISTS sp_handle_quota_exceeded;

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

    IF v_is_fallback = 1 THEN
        LEAVE proc;
    END IF;

    SELECT id INTO v_fallback_profile_id
    FROM radprofile
    WHERE profile_name = 'Fallback'
    LIMIT 1;

    SELECT COALESCE(SUM(data_usage), 0)
    INTO v_data_usage
    FROM radusagestats
    WHERE username = p_username AND day = CURDATE();

    IF v_data_usage >= v_daily_quota THEN
        IF v_profile_id IS NOT NULL AND (v_fallback_profile_id IS NULL OR v_profile_id <> v_fallback_profile_id) THEN
            INSERT INTO user_default_profiles (username, default_profile_id)
            VALUES (p_username, v_profile_id)
            ON DUPLICATE KEY UPDATE default_profile_id = VALUES(default_profile_id);
        END IF;

        UPDATE raduserprofile
        SET profile_id = v_fallback_profile_id,
            is_fallback = 1
        WHERE username = p_username
          AND COALESCE(is_fallback, 0) = 0;

        IF ROW_COUNT() > 0 THEN
            INSERT INTO quota_logs (username, event_type, quota_type, timestamp)
            VALUES (p_username, 'exceeded', 'daily', NOW());
        END IF;
    END IF;
END //

CREATE PROCEDURE sp_handle_quota_exceeded(
    IN p_username VARCHAR(64),
    IN p_quota_type VARCHAR(10)
)
proc: BEGIN
    DECLARE v_fallback_profile_id INT;
    DECLARE v_current_profile_id INT;
    DECLARE v_is_monthly_exceeded TINYINT DEFAULT 0;
    DECLARE v_is_fallback TINYINT DEFAULT 0;

    SELECT id INTO v_fallback_profile_id
    FROM radprofile
    WHERE profile_name = 'Fallback'
    LIMIT 1;

    SELECT profile_id, COALESCE(is_monthly_exceeded, 0), COALESCE(is_fallback, 0)
    INTO v_current_profile_id, v_is_monthly_exceeded, v_is_fallback
    FROM raduserprofile
    WHERE username = p_username
    LIMIT 1;

    IF LOWER(p_quota_type) = 'monthly' AND v_is_monthly_exceeded = 1 THEN
        LEAVE proc;
    END IF;
    IF LOWER(p_quota_type) = 'daily' AND v_is_fallback = 1 THEN
        LEAVE proc;
    END IF;

    IF v_current_profile_id IS NOT NULL AND (v_fallback_profile_id IS NULL OR v_current_profile_id <> v_fallback_profile_id) THEN
        INSERT INTO user_default_profiles (username, default_profile_id)
        VALUES (p_username, v_current_profile_id)
        ON DUPLICATE KEY UPDATE default_profile_id = VALUES(default_profile_id);
    END IF;

    UPDATE raduserprofile
    SET profile_id = v_fallback_profile_id,
        is_monthly_exceeded = IF(LOWER(p_quota_type) = 'monthly', 1, is_monthly_exceeded),
        is_fallback = IF(LOWER(p_quota_type) = 'daily', 1, is_fallback)
    WHERE username = p_username
      AND (
        (LOWER(p_quota_type) = 'monthly' AND COALESCE(is_monthly_exceeded, 0) = 0)
        OR (LOWER(p_quota_type) = 'daily' AND COALESCE(is_fallback, 0) = 0)
      );

    IF ROW_COUNT() > 0 THEN
        INSERT INTO quota_logs (username, event_type, quota_type, timestamp)
        VALUES (p_username, 'exceeded', p_quota_type, NOW());
    END IF;
END //

DELIMITER ;
