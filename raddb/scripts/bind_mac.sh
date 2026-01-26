#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

USERNAME="${1:-}"
MAC_ADDRESS="${2:-}"

if [ -z "$USERNAME" ] || [ -z "$MAC_ADDRESS" ]; then
  exit 0
fi

u="$(sql_escape "$USERNAME")"
m="$(sql_escape "$MAC_ADDRESS")"

mysql_exec "INSERT INTO user_mac (username, mac_address) VALUES ('$u', '$m');" || true

