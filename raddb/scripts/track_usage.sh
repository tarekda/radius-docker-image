#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
MAC_ADDRESS="${2:-}"
BYTES_IN="${3:-0}"
BYTES_OUT="${4:-0}"
SESSION_TIME="${5:-0}"
NAS_IP="${6:-}"

if [ -z "$USERNAME" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"
m="$(sql_escape "$MAC_ADDRESS")"
n="$(sql_escape "$NAS_IP")"

# Numeric inputs: keep only digits to avoid SQL injection via octet fields.
BYTES_IN="${BYTES_IN//[^0-9]/}"
BYTES_OUT="${BYTES_OUT//[^0-9]/}"
SESSION_TIME="${SESSION_TIME//[^0-9]/}"
if [ -z "$BYTES_IN" ]; then BYTES_IN="0"; fi
if [ -z "$BYTES_OUT" ]; then BYTES_OUT="0"; fi
if [ -z "$SESSION_TIME" ]; then SESSION_TIME="0"; fi

mysql_exec "INSERT INTO detailed_usage (username, mac_address, bytes_in, bytes_out, session_time, nas_ip, timestamp) VALUES ('$u', '$m', $BYTES_IN, $BYTES_OUT, $SESSION_TIME, '$n', NOW());" || true