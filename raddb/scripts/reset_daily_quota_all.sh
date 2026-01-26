#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[daily-reset] Starting daily quota + fallback reset at $(date -Is)"

# 1) Reset daily usage (today) to 0 for all users.
# 2) Clear daily FUP flag (is_fallback) for all users.
# 3) Monthly reset: for users whose quota_reset_day == today, clear is_monthly_exceeded (and restore default profile if available).
# NOTE: This does NOT change speeds for already-connected sessions; users will get normal speeds on next re-auth/CoA.
mysql_exec "
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
" || true

echo "[daily-reset] Completed at $(date -Is)"

