#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[daily-reset] Starting daily quota + fallback reset at $(date -Is)"

# 1) Reset daily usage (today) to 0 for all users.
# 2) Clear *daily* FUP flag (is_fallback) ONLY for users not monthly-exceeded, and restore default profile if available.
#    (Monthly-exceeded users must remain on fallback until their cycle restarts.)
# 3) Monthly reset (per-user): clear is_monthly_exceeded for users whose monthly cycle
#    restarts TODAY (their quota_reset_day / manual anchor — see fn_quota_cycle_start).
# 4) Restore normal speed for *currently online* users whose daily/monthly fallback was cleared (CoA).

# Capture affected users BEFORE we clear flags (so we can CoA them after restore).
ensure_mysql_defaults
DAILY_USERS="$(
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e \
    "SELECT username FROM raduserprofile WHERE is_fallback = 1 AND COALESCE(is_monthly_exceeded, 0) = 0;" 2>/dev/null || true
)"

# Users whose monthly cycle restarts today also get cleared; capture them for CoA restore.
MONTHLY_USERS="$(
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e \
    "SELECT username FROM raduserprofile WHERE COALESCE(is_monthly_exceeded, 0) = 1 AND fn_quota_cycle_start(username) = CURDATE();" 2>/dev/null || true
)"

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

  -- Monthly reset (per-user): clear monthly exceeded and restore defaults for users
  -- whose cycle restarts today (quota_reset_day / manual anchor via fn_quota_cycle_start).
  -- Materialize the user set first: MySQL forbids calling a function that reads
  -- raduserprofile from within an UPDATE of raduserprofile (error 1442).
  DROP TEMPORARY TABLE IF EXISTS tmp_monthly_resets;
  CREATE TEMPORARY TABLE tmp_monthly_resets AS
    SELECT username FROM raduserprofile
    WHERE COALESCE(is_monthly_exceeded, 0) = 1
      AND fn_quota_cycle_start(username) = CURDATE();

  UPDATE raduserprofile up
  JOIN tmp_monthly_resets t
    ON BINARY t.username = BINARY up.username
  LEFT JOIN user_default_profiles udp
    ON BINARY udp.username = BINARY up.username
  SET
    up.is_monthly_exceeded = 0,
    up.is_fallback = 0,
    up.profile_id = COALESCE(udp.default_profile_id, up.profile_id);

  DROP TEMPORARY TABLE IF EXISTS tmp_monthly_resets;

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

