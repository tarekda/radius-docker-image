#!/bin/bash
# bootstrap_schema.sh: create missing tables on existing deployments.
#
# Why:
# - MySQL docker init scripts under mysql/init only run on first DB initialization.
# - If you already had a database, new tables like `user_default_profiles` won't exist.
# - FreeRADIUS quota logic relies on it (default/original plan tracking).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[bootstrap] Ensuring schema objects exist..."

# Drop legacy procedures removed from the solution (no runtime callers).
mysql_exec "DROP PROCEDURE IF EXISTS kill_session;" || true
mysql_exec "DROP PROCEDURE IF EXISTS sp_get_online_users;" || true

# Keep this idempotent and safe. Avoid FK creation here (can fail on drifted schemas).
mysql_exec "
CREATE TABLE IF NOT EXISTS user_default_profiles (
  username VARCHAR(64) NOT NULL,
  default_profile_id INT NOT NULL,
  PRIMARY KEY (username),
  INDEX idx_udp_default_profile_id (default_profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
" || true

# Per-interim/session snapshots for exact rolling-window usage checks.
mysql_exec "
CREATE TABLE IF NOT EXISTS session_usage_snapshots (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  username VARCHAR(64) NOT NULL,
  session_id VARCHAR(64) NOT NULL,
  nas_ip VARCHAR(15),
  framed_ip VARCHAR(15),
  acct_status ENUM('start', 'interim', 'stop') NOT NULL,
  bytes_in_total BIGINT NOT NULL DEFAULT 0,
  bytes_out_total BIGINT NOT NULL DEFAULT 0,
  delta_bytes_in BIGINT NOT NULL DEFAULT 0,
  delta_bytes_out BIGINT NOT NULL DEFAULT 0,
  delta_total BIGINT NOT NULL DEFAULT 0,
  snapshot_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_sus_user_time (username, snapshot_at),
  INDEX idx_sus_session_time (session_id, snapshot_at),
  INDEX idx_sus_nas_time (nas_ip, snapshot_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
" || true

# Per-user free-night flag (legacy DBs may not have this column yet).
mysql_exec "
ALTER TABLE raduserprofile
  ADD COLUMN freenight TINYINT(1) DEFAULT 0;
" || true

# Subscription expiry (walled-garden IP + optional per-user override in raduserprofile.expiry_framed_ip)
mysql_exec "
ALTER TABLE raduserprofile
  ADD COLUMN expires_at DATETIME NULL DEFAULT NULL;
" || true
mysql_exec "
ALTER TABLE raduserprofile
  ADD COLUMN expiry_framed_ip VARCHAR(45) NULL DEFAULT NULL;
" || true

# Optional manual monthly billing cycle anchor (backend + FreeRADIUS monthly window).
mysql_exec "
ALTER TABLE raduserprofile
  ADD COLUMN quota_cycle_start_date DATE NULL DEFAULT NULL;
" || true

# Legacy DBs may have CHECK on account_status that omits 'expired' / 'terminated', which breaks
# RADIUS + backend expiry updates. Safe to drop: app + FreeRADIUS enforce allowed values.
# If this fails (unknown constraint name), list CHECKs and adjust — see mysql/alter_raduserprofile_expiry.sql
mysql_exec "
ALTER TABLE raduserprofile DROP CHECK raduserprofile_chk_1;
" || true

echo "[bootstrap] Deduplicating Fallback profiles (legacy DBs without unique index)..."

# Legacy deployments may have accumulated duplicate rows named 'Fallback' because
# bootstrap INSERT ran on every container start before uq_radprofile_profile_name existed.
mysql_exec "
SET @keep_id := (SELECT MIN(id) FROM radprofile WHERE profile_name = 'Fallback');
UPDATE raduserprofile
   SET profile_id = @keep_id
 WHERE @keep_id IS NOT NULL
   AND profile_id IN (
     SELECT id FROM (
       SELECT id FROM radprofile WHERE profile_name = 'Fallback' AND id <> @keep_id
     ) AS dup_profiles
   );
UPDATE user_default_profiles
   SET default_profile_id = @keep_id
 WHERE @keep_id IS NOT NULL
   AND default_profile_id IN (
     SELECT id FROM (
       SELECT id FROM radprofile WHERE profile_name = 'Fallback' AND id <> @keep_id
     ) AS dup_profiles
   );
DELETE FROM radprofile
 WHERE profile_name = 'Fallback'
   AND @keep_id IS NOT NULL
   AND id <> @keep_id;
" || true

idx_count="$(mysql_one "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'radprofile' AND INDEX_NAME = 'uq_radprofile_profile_name';")"
if [ "${idx_count:-0}" = "0" ]; then
  echo "[bootstrap] Adding unique index on radprofile.profile_name..."
  mysql_exec "ALTER TABLE radprofile ADD UNIQUE KEY uq_radprofile_profile_name (profile_name);" || true
fi

echo "[bootstrap] Ensuring Fallback (FUP) profile speed is 2048k..."

# Make sure the Fallback profile exists, and enforce its speed.
# - INSERT only matters for fresh DBs without the row.
# - ON DUPLICATE KEY only updates speeds (doesn't touch quotas/time windows).
mysql_exec "
INSERT INTO radprofile (profile_name, daily_quota, monthly_quota, night_start, night_end, speed_down, speed_up)
VALUES ('Fallback', 104857600, 3221225472, '00:00:00', '06:00:00', 2048, 2048)
ON DUPLICATE KEY UPDATE
  speed_down = VALUES(speed_down),
  speed_up = VALUES(speed_up);
" || true

patch_sql="${SCRIPT_DIR}/patch_quota_procedures.sql"
if [ -f "$patch_sql" ]; then
  echo "[bootstrap] Updating quota procedures (prevent duplicate exceeded logs)..."
  ensure_mysql_defaults
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" < "$patch_sql" 2>/dev/null || true
fi

# Quota cycle window function + per-user monthly reset + aligned remaining_quota view.
patch_sql="${SCRIPT_DIR}/patch_quota_cycle.sql"
if [ -f "$patch_sql" ]; then
  echo "[bootstrap] Updating quota cycle function/procedures/view..."
  ensure_mysql_defaults
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" < "$patch_sql" 2>/dev/null || true

  # The accounting flow depends on this function; fail LOUDLY if it's missing.
  # Most common cause: binary logging enabled without log_bin_trust_function_creators=1
  # and a non-SUPER SQL user (see mysql/conf.d/my.cnf).
  fn_count="$(mysql_one "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'fn_quota_cycle_start';")"
  if [ "${fn_count:-0}" = "0" ]; then
    echo "[bootstrap] ERROR: fn_quota_cycle_start was NOT created — monthly quota checks WILL fail." >&2
    echo "[bootstrap] Set log_bin_trust_function_creators=1 on the MySQL server, or grant the SQL user function-creation rights, then restart." >&2
  fi
fi

# Indexes that keep the nightly purge cheap (skip if already present).
for spec in \
  "session_usage_snapshots:snapshot_at:idx_sus_snapshot_at" \
  "detailed_usage:timestamp:idx_du_timestamp" \
  "connection_logs:timestamp:idx_cl_timestamp" \
  "quota_logs:timestamp:idx_ql_timestamp"; do
  tbl="${spec%%:*}"; rest="${spec#*:}"; col="${rest%%:*}"; idx="${rest#*:}"
  idx_count="$(mysql_one "SELECT COUNT(*) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '${tbl}' AND INDEX_NAME = '${idx}';")"
  if [ "${idx_count:-0}" = "0" ]; then
    echo "[bootstrap] Adding index ${idx} on ${tbl}(${col})..."
    mysql_exec "ALTER TABLE ${tbl} ADD INDEX ${idx} (\`${col}\`);" || true
  fi
done

# Log retention: purge procedure + nightly event.
patch_sql="${SCRIPT_DIR}/patch_log_retention.sql"
if [ -f "$patch_sql" ]; then
  echo "[bootstrap] Updating log retention purge procedure/event..."
  ensure_mysql_defaults
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" < "$patch_sql" 2>/dev/null || true
fi

echo "[bootstrap] Done."

