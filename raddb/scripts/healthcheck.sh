#!/bin/bash
# Container healthcheck: verify RADIUS answers AND MySQL is reachable.
#
# Status-Server alone can report healthy while the SQL backend is down.
# Requires:
# - the `healthcheck` client in clients.conf (127.0.0.1, HEALTHCHECK_SECRET)
# - status_server = yes (FreeRADIUS default)
# - MYSQL_DEFAULTS_FILE written by start.sh
set -u

SECRET="${HEALTHCHECK_SECRET:-radius-healthcheck}"
MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-/run/freeradius-mysql.cnf}"

if [ ! -f "$MYSQL_DEFAULTS_FILE" ]; then
  echo "healthcheck: missing MySQL defaults file" >&2
  exit 1
fi

if ! mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -e "SELECT 1;" >/dev/null 2>&1; then
  echo "healthcheck: MySQL unreachable" >&2
  exit 1
fi

echo "Message-Authenticator = 0x00" | radclient -q -r 1 -t 3 127.0.0.1:1812 status "$SECRET"
