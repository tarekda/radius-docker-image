-- =============================================================================
-- raduserprofile: subscription expiry (existing databases)
-- =============================================================================
-- Run against your RADIUS schema (default database name: `radius`).
--
--   mysql -u USER -p radius < alter_raduserprofile_expiry.sql
--
-- If you see "Duplicate column name", those columns already exist — safe to skip.
-- =============================================================================

USE radius;

-- Expiry datetime (NULL = no time-based expiry; RADIUS ignores expiry logic)
ALTER TABLE raduserprofile
  ADD COLUMN expires_at DATETIME NULL DEFAULT NULL  COMMENT 'When set and in the past, RADIUS may set account_status to expired on auth';

-- Optional per-user framed IP for expired/captive sessions (overrides EXPIRY_FRAMED_IP env)
ALTER TABLE raduserprofile
  ADD COLUMN expiry_framed_ip VARCHAR(45) NULL DEFAULT NULL
  COMMENT 'Walled-garden framed IP; empty = use RADIUS server default';

-- Optional indexes (uncomment if you filter/report by expiry often)
-- CREATE INDEX idx_raduserprofile_expires_at ON raduserprofile (expires_at);
-- CREATE INDEX idx_raduserprofile_account_expires ON raduserprofile (account_status, expires_at);

-- -----------------------------------------------------------------------------
-- CHECK on account_status
-- -----------------------------------------------------------------------------
-- If you see: Check constraint 'raduserprofile_chk_1' is violated — run once:
--   mysql -u USER -p radius < fix_raduserprofile_chk1_expired.sql
-- Or uncomment:
-- ALTER TABLE raduserprofile DROP CHECK raduserprofile_chk_1;

-- If the name differs, list CHECKs then drop the one that restricts account_status:
--
--   SELECT tc.CONSTRAINT_NAME, cc.CHECK_CLAUSE
--   FROM information_schema.TABLE_CONSTRAINTS tc
--   JOIN information_schema.CHECK_CONSTRAINTS cc
--     ON tc.CONSTRAINT_SCHEMA = cc.CONSTRAINT_SCHEMA
--    AND tc.CONSTRAINT_NAME = cc.CONSTRAINT_NAME
--   WHERE tc.TABLE_SCHEMA = DATABASE()
--     AND tc.TABLE_NAME = 'raduserprofile'
--     AND tc.CONSTRAINT_TYPE = 'CHECK';
--
-- If DROP fails because chk_1 was the only CHECK and it enforced quota_reset_day, re-add:
--   ALTER TABLE raduserprofile ADD CONSTRAINT raduserprofile_chk_quota_reset_day
--     CHECK (quota_reset_day BETWEEN 1 AND 31);
