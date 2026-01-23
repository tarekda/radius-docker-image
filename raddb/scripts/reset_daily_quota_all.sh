#!/bin/bash
set -euo pipefail

RADIUS_DB_HOST="${SQL_SERVER:-host.docker.internal}"
RADIUS_DB_USER="${SQL_USER:-radius}"
RADIUS_DB_PASSWORD="${SQL_PASSWORD:-password}"
RADIUS_DB_NAME="${SQL_DATABASE:-radius}"
RADIUS_DB_PORT="${SQL_PORT:-3306}"

echo "[daily-reset] Starting daily quota + fallback reset at $(date -Is)"

# 1) Reset daily usage (today) to 0 for all users.
# 2) Clear daily FUP flag (is_fallback) for all users.
# 3) Monthly reset: for users whose quota_reset_day == today, clear is_monthly_exceeded (and restore default profile if available).
# NOTE: This does NOT change speeds for already-connected sessions; users will get normal speeds on next re-auth/CoA.
mysql -h "$RADIUS_DB_HOST" -P "$RADIUS_DB_PORT" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD" -D "$RADIUS_DB_NAME" -e "
  UPDATE raduserprofile
     SET is_fallback = 0;

  -- Monthly reset happens per-user on their quota_reset_day.
  -- Clear monthly exceeded flag, and (if configured) restore their default profile.
  UPDATE raduserprofile up
  LEFT JOIN user_default_profiles udp
    ON udp.username = up.username
     SET up.is_monthly_exceeded = 0,
         up.profile_id = COALESCE(udp.default_profile_id, up.profile_id)
   WHERE up.quota_reset_day = DAY(CURDATE());

  -- Your live radusagestats schema uses (username, day, data_usage) only.
  UPDATE radusagestats
     SET data_usage = 0
   WHERE day = CURDATE();

  INSERT INTO radusagestats (username, day, data_usage)
  SELECT username, CURDATE(), 0
  FROM raduserprofile
  ON DUPLICATE KEY UPDATE data_usage = 0;
"

echo "[daily-reset] Completed at $(date -Is)"

