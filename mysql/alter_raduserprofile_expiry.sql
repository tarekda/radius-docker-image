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
-- Optional: widen/remove CHECK on account_status (older init scripts only)
-- -----------------------------------------------------------------------------
-- If inserts/updates with account_status = 'expired' or 'terminated' fail with
-- CHECK constraint, list constraints then drop/recreate:
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
-- Example (replace CONSTRAINT_NAME with the name from the query above):
--   ALTER TABLE raduserprofile DROP CHECK raduserprofile_chk_1;
--
-- Or replace the column without a CHECK (application validates statuses):
--   ALTER TABLE raduserprofile
--     MODIFY COLUMN account_status VARCHAR(20) NOT NULL DEFAULT 'active';
