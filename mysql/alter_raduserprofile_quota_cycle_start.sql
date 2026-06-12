-- Per-user manual monthly cycle anchor (optional).
-- When set, monthly usage is counted from this date; next reset = date + 1 month.
-- When NULL, monthly window follows quota_reset_day (same as FreeRADIUS sql mod).
--
--   mysql -u USER -p radius < alter_raduserprofile_quota_cycle_start.sql
--
-- If you see "Duplicate column name", the column already exists — safe to skip.

USE radius;

ALTER TABLE raduserprofile
  ADD COLUMN quota_cycle_start_date DATE NULL DEFAULT NULL
  AFTER quota_reset_day;
