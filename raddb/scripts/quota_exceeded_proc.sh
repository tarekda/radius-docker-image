#!/bin/bash
# quota_exceeded_proc.sh: call quota-exceeded stored procedures in MySQL.
#
# Usage:
#   quota_exceeded_proc.sh <username> <daily|monthly>
#
# This is invoked from FreeRADIUS accounting (Interim-Update / Stop) after radusagestats is updated,
# so the DB becomes the source of truth:
# - daily:   CALL sp_handle_daily_quota_exceeded(username)
# - monthly: CALL sp_handle_quota_exceeded(username, 'monthly')
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
TYPE="${2:-}"

if [ -z "$USERNAME" ] || [ -z "$TYPE" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"
t="$(echo "$TYPE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

if [ "$t" = "daily" ]; then
  mysql_exec "CALL sp_handle_daily_quota_exceeded('${u}');" || true
  exit 0
fi

if [ "$t" = "monthly" ]; then
  mysql_exec "CALL sp_handle_quota_exceeded('${u}', 'monthly');" || true
  exit 0
fi

exit 0

