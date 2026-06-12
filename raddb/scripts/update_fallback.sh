#!/bin/bash
# update_fallback.sh: Legacy helper — sets is_fallback only (profile switch is done by stored procedures).
# Does NOT write quota_logs (procedures are the single source of truth for exceeded events).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"

already="$(mysql_one "SELECT COALESCE(is_fallback, 0) FROM raduserprofile WHERE username = '${u}' LIMIT 1;")"
if [ "${already:-0}" = "1" ]; then
  exit 0
fi

mysql_exec "UPDATE raduserprofile SET is_fallback = 1 WHERE username = '${u}';" || true
