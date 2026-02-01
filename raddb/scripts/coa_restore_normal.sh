#!/bin/bash
# coa_restore_normal.sh: Send MikroTik CoA to restore user's *current* profile rate mid-session.
#
# Usage:
#   coa_restore_normal.sh <username> <acct_session_id> <nas_ip> <framed_ip>
#
# Notes:
# - CoA secret is read from the `nas` table (nasname = NAS IP).
# - Rate is derived from raduserprofile.profile_id (after nightly resets restore it).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
SESSION_ID="${2:-}"
NAS_IP="${3:-}"
FRAMED_IP="${4:-}"

if [ -z "$USERNAME" ] || [ -z "$SESSION_ID" ] || [ -z "$NAS_IP" ]; then
  echo "coa_restore_normal.sh: missing args (username/session_id/nas_ip)" >&2
  exit 0
fi

get_one() { mysql_one "$1"; }

nas_esc="$(sql_escape "$NAS_IP")"
SECRET="$(get_one "SELECT secret FROM nas WHERE nasname='${nas_esc}' LIMIT 1;")"
if [ -z "$SECRET" ]; then
  echo "coa_restore_normal.sh: no secret found in nas table for NAS ${NAS_IP}" >&2
  exit 0
fi

u_esc="$(sql_escape "$USERNAME")"
RATE_LIMIT="$(get_one "SELECT CONCAT(p.speed_down,'k/',p.speed_up,'k') \
                       FROM raduserprofile up \
                       JOIN radprofile p ON p.id = up.profile_id \
                       WHERE up.username='${u_esc}' \
                       LIMIT 1;")"
if [ -z "$RATE_LIMIT" ]; then
  # No profile/rate found; do nothing.
  exit 0
fi

PAYLOAD="User-Name = ${USERNAME}
Acct-Session-Id = ${SESSION_ID}
Mikrotik-Rate-Limit := \"${RATE_LIMIT}\""

if [ -n "$FRAMED_IP" ]; then
  PAYLOAD="${PAYLOAD}
Framed-IP-Address = ${FRAMED_IP}"
fi

echo "$PAYLOAD" | radclient "${NAS_IP}:3799" coa "$SECRET" >/dev/null 2>&1 || true

