#!/bin/bash

# Wait for MySQL to be ready
until mysql -h"$SQL_SERVER" -P"$SQL_PORT" -u"$SQL_USER" -p"$SQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1
do
    echo "Waiting for MySQL to be ready..."
    sleep 1
done

echo "MySQL is ready"

# Ensure scripts are executable (Windows hosts may strip +x during build/copy).
chmod +x /opt/freeradius/3.0/scripts/*.sh >/dev/null 2>&1 || true

# Run a daily reset at 00:00 (container local time).
# - Resets daily usage rows for today to 0
# - Clears daily fallback flag (is_fallback)
# - Clears monthly exceeded for users whose quota_reset_day is today
#
# Control via env:
#   DAILY_RESET_ENABLED=1|0 (default 1)
#   DAILY_RESET_AT=HH:MM (default 00:00)
if [ "${DAILY_RESET_ENABLED:-1}" = "1" ]; then
  (
    set -e
    AT="${DAILY_RESET_AT:-00:00}"
    echo "Daily reset enabled at ${AT} (TZ=${TZ:-system})"

    while true; do
      now="$(date +%s)"
      # Today's scheduled timestamp
      target="$(date -d "$(date +%F) ${AT}:00" +%s 2>/dev/null || true)"
      if [ -z "${target}" ]; then
        # Fallback parsing (some date versions accept HH:MM without seconds)
        target="$(date -d "$(date +%F) ${AT}" +%s)"
      fi
      if [ "${target}" -le "${now}" ]; then
        target="$(date -d "tomorrow ${AT}:00" +%s 2>/dev/null || date -d "tomorrow ${AT}" +%s)"
      fi

      sleep_for=$(( target - now ))
      echo "Next daily reset in ${sleep_for}s (at $(date -d "@${target}" -Is))"
      sleep "${sleep_for}"

      /opt/freeradius/3.0/scripts/reset_daily_quota_all.sh || true

      # Prevent double-run in case of clock drift / DST jumps
      sleep 60
    done
  ) &
fi

# Start FreeRADIUS.
# - Default: foreground + log to stdout (so Promtail/Loki can collect logs)
# - Debug: set FREERADIUS_DEBUG=1 to run verbose (-X)
if [ "${FREERADIUS_DEBUG:-0}" = "1" ]; then
  echo "Starting FreeRADIUS in DEBUG mode (-X)"
  exec /usr/sbin/freeradius -X
else
  echo "Starting FreeRADIUS (foreground, stdout logging)"
  exec /usr/sbin/freeradius -f -l stdout
fi