-- patch_log_retention.sql: bounded retention for append-only log tables.
--
-- Applied idempotently on every container start by bootstrap_schema.sh.
-- Without this, session_usage_snapshots / detailed_usage / connection_logs /
-- quota_logs grow forever and slow down both quota math and dashboards.
--
-- Retention windows (days):
--   session_usage_snapshots : 30   (debug/audit trail of per-packet deltas)
--   detailed_usage          : 90   (raw per-packet usage rows)
--   connection_logs         : 90   (auth attempts/accept/reject; rate-limit window is 5 min)
--   quota_logs              : 365  (exceeded/reset history, useful for billing disputes)
--
-- Deletes are batched (20k rows) to avoid long locks on busy tables.

USE radius;

DROP PROCEDURE IF EXISTS sp_purge_old_logs;

DELIMITER //

CREATE PROCEDURE sp_purge_old_logs()
BEGIN
    DECLARE v_batch INT DEFAULT 20000;
    DECLARE v_rows INT DEFAULT 0;

    REPEAT
        DELETE FROM session_usage_snapshots
         WHERE snapshot_at < NOW() - INTERVAL 30 DAY
         LIMIT 20000;
        SET v_rows = ROW_COUNT();
    UNTIL v_rows < v_batch END REPEAT;

    REPEAT
        DELETE FROM detailed_usage
         WHERE timestamp < NOW() - INTERVAL 90 DAY
         LIMIT 20000;
        SET v_rows = ROW_COUNT();
    UNTIL v_rows < v_batch END REPEAT;

    REPEAT
        DELETE FROM connection_logs
         WHERE timestamp < NOW() - INTERVAL 90 DAY
         LIMIT 20000;
        SET v_rows = ROW_COUNT();
    UNTIL v_rows < v_batch END REPEAT;

    REPEAT
        DELETE FROM quota_logs
         WHERE timestamp < NOW() - INTERVAL 365 DAY
         LIMIT 20000;
        SET v_rows = ROW_COUNT();
    UNTIL v_rows < v_batch END REPEAT;
END //

DELIMITER ;

-- Run nightly at 03:30 (off-peak, away from the 00:00 quota reset).
DROP EVENT IF EXISTS purge_old_logs_event;
CREATE EVENT purge_old_logs_event
ON SCHEDULE EVERY 1 DAY
STARTS (DATE_ADD(CURDATE(), INTERVAL 1 DAY) + INTERVAL 210 MINUTE)
DO
    CALL sp_purge_old_logs();
