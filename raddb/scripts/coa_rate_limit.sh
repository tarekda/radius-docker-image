#!/bin/bash
# coa_rate_limit.sh: Send MikroTik CoA to apply fallback Mikrotik-Rate-Limit mid-session.
#
# Usage:
#   coa_rate_limit.sh <username> <acct_session_id> <nas_ip> <framed_ip>
#
# Notes:
# - Requires MikroTik: /radius incoming set accept=yes port=3799
# - CoA secret is read from the `nas` table (nasname = NAS IP).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
SESSION_ID="${2:-}"
NAS_IP="${3:-}"
FRAMED_IP="${4:-}"

if [ -z "$USERNAME" ] || [ -z "$SESSION_ID" ] || [ -z "$NAS_IP" ]; then
  echo "coa_rate_limit.sh: missing args (username/session_id/nas_ip)" >&2
  exit 0
fi

get_one() { mysql_one "$1"; }

# CoA secret for this NAS
nas_esc="$(sql_escape "$NAS_IP")"
SECRET="$(get_one "SELECT secret FROM nas WHERE nasname='${nas_esc}' LIMIT 1;")"
if [ -z "$SECRET" ]; then
  echo "coa_rate_limit.sh: no secret found in nas table for NAS ${NAS_IP}" >&2
  exit 0
fi

# Fallback rate string must match what you already send in Access-Accept.
# Keep the same order as authorize_reply_query (speed_down/speed_up).
RATE_LIMIT="$(get_one "SELECT CONCAT(speed_down,'k/',speed_up,'k') FROM radprofile WHERE profile_name='Fallback' LIMIT 1;")"
if [ -z "$RATE_LIMIT" ]; then
  echo "coa_rate_limit.sh: could not resolve Fallback rate from radprofile; using 256k/128k" >&2
  RATE_LIMIT="256k/128k"
fi

PAYLOAD="User-Name = ${USERNAME}
Acct-Session-Id = ${SESSION_ID}
Mikrotik-Rate-Limit := \"${RATE_LIMIT}\""

if [ -n "$FRAMED_IP" ]; then
  PAYLOAD="${PAYLOAD}
Framed-IP-Address = ${FRAMED_IP}"
fi

# IMPORTANT:
# Do not use `-x` here. FreeRADIUS exec parsing can choke on debug output,
# causing "Failed parsing output" / "unfinished request" errors.
echo "$PAYLOAD" | radclient "${NAS_IP}:3799" coa "$SECRET" >/dev/null 2>&1 || true

