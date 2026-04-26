-- =============================================================================
-- connection_logs: dashboard-friendly indexes for existing databases
-- =============================================================================
-- Run against your RADIUS schema (default database name: `radius`).
--
--   mysql -u USER -p radius < alter_connection_logs_indexes.sql
--
-- MySQL docker init scripts only run when the database volume is first created.
-- Use this file for already-running installations.
-- =============================================================================

USE radius;

CREATE TABLE IF NOT EXISTS connection_log_hourly_stats (
    bucket DATETIME NOT NULL PRIMARY KEY,
    attempts BIGINT NOT NULL DEFAULT 0,
    accepted BIGINT NOT NULL DEFAULT 0,
    rejected BIGINT NOT NULL DEFAULT 0,
    timeout BIGINT NOT NULL DEFAULT 0,
    error BIGINT NOT NULL DEFAULT 0,
    total BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @idx_exists := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'connection_logs'
    AND INDEX_NAME = 'idx_connection_logs_timestamp_status'
);

SET @sql := IF(
  @idx_exists = 0,
  'ALTER TABLE connection_logs ADD INDEX idx_connection_logs_timestamp_status (timestamp, status)',
  'SELECT ''idx_connection_logs_timestamp_status already exists'' AS message'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
