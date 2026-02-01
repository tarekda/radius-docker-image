#!/bin/bash
# clear_stale_daily_fallback.sh:
# Clear DAILY fallback (is_fallback) that is stale from a previous day.
#
# Why:
# - Users can be put into fallback when they exceed daily quota.
# - They should be cleared at midnight.
# - If the RADIUS container is restarted after midnight (or the scheduled job was missed),
#   users can remain stuck in FUP even though they haven't exceeded today.
#
# Safety:
# - Does NOT touch radusagestats (so no risk of wiping today's usage).
# - Does NOT clear monthly exceeded users.
# - Does NOT clear users who have a "daily exceeded" log entry for today.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[startup] Clearing stale daily fallback flags (best-effort)..."

mysql_exec "
  UPDATE raduserprofile up
  LEFT JOIN user_default_profiles udp
    ON BINARY udp.username = BINARY up.username
  SET
    up.is_fallback = 0,
    up.profile_id = COALESCE(udp.default_profile_id, up.profile_id)
  WHERE COALESCE(up.is_fallback, 0) = 1
    AND COALESCE(up.is_monthly_exceeded, 0) = 0
    AND NOT EXISTS (
      SELECT 1
      FROM quota_logs q
      WHERE BINARY q.username = BINARY up.username
        AND q.event_type = 'exceeded'
        AND q.quota_type = 'daily'
        AND DATE(q.timestamp) = CURDATE()
    );
" || true

echo "[startup] Done."

