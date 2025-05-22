#!/bin/bash

# Wait for MySQL to be ready
until mysql -h"$SQL_SERVER" -P"$SQL_PORT" -u"$SQL_USER" -p"$SQL_PASSWORD" -e "SELECT 1;" >/dev/null 2>&1
do
    echo "Waiting for MySQL to be ready..."
    sleep 1
done

echo "MySQL is ready"

# Start FreeRADIUS in debug mode
/usr/sbin/freeradius -f