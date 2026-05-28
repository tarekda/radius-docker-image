-- =============================================================================
-- RADIUS auth/accounting hot-path performance fixes for existing databases
-- =============================================================================
-- Run against your RADIUS schema (default database name: `radius`).
--
--   mysql -u USER -p radius < alter_radius_auth_performance.sql
--
-- Keeps username comparisons index-friendly after removing forced COLLATE clauses
-- from FreeRADIUS SQL config.
-- =============================================================================

USE radius;

SET @idx_exists := (
  SELECT COUNT(*)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'raduserprofile'
    AND INDEX_NAME = 'idx_raduserprofile_username'
);

SET @sql := IF(
  @idx_exists = 0,
  'ALTER TABLE raduserprofile ADD INDEX idx_raduserprofile_username (username)',
  'SELECT ''idx_raduserprofile_username already exists'' AS message'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

ALTER TABLE user_default_profiles
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;

ALTER TABLE session_usage_snapshots
  CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
