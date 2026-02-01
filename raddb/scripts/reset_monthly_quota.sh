#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"

mysql_exec "UPDATE raduserprofile SET is_monthly_exceeded = 0, profile_id = (SELECT default_profile_id FROM user_default_profiles WHERE BINARY username = BINARY '$u') WHERE BINARY username = BINARY '$u' AND is_monthly_exceeded = 1;" || true
mysql_exec "UPDATE raduserprofile SET is_fallback = 0 WHERE username = '$u';" || true