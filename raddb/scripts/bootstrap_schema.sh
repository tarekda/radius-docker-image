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

# Legacy DBs may have CHECK on account_status that omits 'expired' / 'terminated', which breaks
# RADIUS + backend expiry updates. Safe to drop: app + FreeRADIUS enforce allowed values.
# If this fails (unknown constraint name), list CHECKs and adjust — see mysql/alter_raduserprofile_expiry.sql
mysql_exec "
ALTER TABLE raduserprofile DROP CHECK raduserprofile_chk_1;
" || true

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

echo "[bootstrap] Done."

