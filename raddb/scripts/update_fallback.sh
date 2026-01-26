#!/bin/bash
# update_fallback.sh: Update raduserprofile for a given username
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"

mysql_exec "UPDATE raduserprofile SET is_fallback = 1 WHERE username = '${u}';" || true
mysql_exec "INSERT INTO quota_logs (username, event_type, quota_type, timestamp) VALUES ('${u}', 'exceeded', 'daily', NOW());" || true
