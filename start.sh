#!/bin/bash

# Wait for MySQL to be ready
until mysql -h"$SQL_SERVER" -P"$SQL_PORT" -u"$SQL_USER" -p"$SQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1
do
    echo "Waiting for MySQL to be ready..."
    sleep 1
done

echo "MySQL is ready"

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