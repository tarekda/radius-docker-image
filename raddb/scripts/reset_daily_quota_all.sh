#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[daily-reset] Starting daily quota + fallback reset at $(date -Is)"

# 1) Reset daily usage (today) to 0 for all users.
# 2) Clear *daily* FUP flag (is_fallback) ONLY for users not monthly-exceeded, and restore default profile if available.
#    (Monthly-exceeded users must remain on fallback until their quota_reset_day.)
# 3) Monthly reset (global): on the 1st day of the month at 00:00, clear is_monthly_exceeded and restore defaults.
# 4) Restore normal speed for *currently online* users whose daily/monthly fallback was cleared (CoA).

# Capture affected users BEFORE we clear flags (so we can CoA them after restore).
ensure_mysql_defaults
DAILY_USERS="$(
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e \
    "SELECT username FROM raduserprofile WHERE is_fallback = 1 AND COALESCE(is_monthly_exceeded, 0) = 0;" 2>/dev/null || true
)"

# On day 1, we also clear monthly exceeded; capture those users too for CoA restore.
MONTHLY_USERS=""
if [ "$(date +%d)" = "01" ]; then
  MONTHLY_USERS="$(
    mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e \
      "SELECT username FROM raduserprofile WHERE COALESCE(is_monthly_exceeded, 0) = 1;" 2>/dev/null || true
  )"
fi

mysql_exec "
  -- Clear DAILY fallback only (do not touch monthly exceeded users).
  -- Also restore the user default profile when we previously switched them to the Fallback profile.
  UPDATE raduserprofile up
  LEFT JOIN user_default_profiles udp
    ON BINARY udp.username = BINARY up.username
  SET
    up.is_fallback = 0,
    up.profile_id = COALESCE(udp.default_profile_id, up.profile_id)
  WHERE up.is_fallback = 1
    AND COALESCE(up.is_monthly_exceeded, 0) = 0;

  -- Monthly reset (global): on the 1st day of the month at 00:00, clear monthly exceeded and restore defaults.
  UPDATE raduserprofile up
  LEFT JOIN user_default_profiles udp
    ON BINARY udp.username = BINARY up.username
  SET
    up.is_monthly_exceeded = 0,
    up.is_fallback = 0,
    up.profile_id = COALESCE(udp.default_profile_id, up.profile_id)
  WHERE DAY(CURDATE()) = 1
    AND COALESCE(up.is_monthly_exceeded, 0) = 1;

  -- Your live radusagestats schema uses (username, day, data_usage) only.
  UPDATE radusagestats
     SET data_usage = 0
   WHERE day = CURDATE();

  INSERT INTO radusagestats (username, day, data_usage)
  SELECT username, CURDATE(), 0
  FROM raduserprofile
  ON DUPLICATE KEY UPDATE data_usage = 0;
" || true

# Restore normal speed mid-session for users we just restored (best-effort CoA).
restore_user_sessions() {
  local username="$1"
  [ -n "$username" ] || return 0

  local u_esc
  u_esc="$(sql_escape "$username")"

  # acctsessionid \t nasipaddress \t framedipaddress
  local rows
  rows="$(
    mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e \
      "SELECT acctsessionid, nasipaddress, framedipaddress FROM radacct WHERE acctstoptime IS NULL AND username='${u_esc}';" 2>/dev/null || true
  )"

  [ -n "$rows" ] || return 0

  while IFS=$'\t' read -r sid nas_ip framed_ip; do
    [ -n "${sid:-}" ] || continue
    [ -n "${nas_ip:-}" ] || continue
    /opt/freeradius/3.0/scripts/coa_restore_normal.sh "$username" "$sid" "$nas_ip" "${framed_ip:-}" || true
  done <<< "$rows"
}

if [ -n "$DAILY_USERS" ]; then
  while IFS= read -r u; do
    restore_user_sessions "$u"
  done <<< "$DAILY_USERS"
fi

if [ -n "$MONTHLY_USERS" ]; then
  while IFS= read -r u; do
    restore_user_sessions "$u"
  done <<< "$MONTHLY_USERS"
fi

echo "[daily-reset] Completed at $(date -Is)"

