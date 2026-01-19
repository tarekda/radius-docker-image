#!/bin/bash

USERNAME=$1
MAC_ADDRESS=$2
BYTES_IN=$3
BYTES_OUT=$4
SESSION_TIME=$5
NAS_IP=$6
RADIUS_DB_HOST="${SQL_SERVER:-host.docker.internal}"
RADIUS_DB_USER="${SQL_USER:-radius}"
RADIUS_DB_PASSWORD="${SQL_PASSWORD:-password}"
RADIUS_DB_NAME="${SQL_DATABASE:-radius}"
RADIUS_DB_PORT="${SQL_PORT:-3306}"

mysql -h "$RADIUS_DB_HOST" -P "$RADIUS_DB_PORT" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD" -D "$RADIUS_DB_NAME" -e "
    INSERT INTO detailed_usage (username, mac_address, bytes_in, bytes_out, session_time, nas_ip, timestamp)
    VALUES ('$USERNAME', '$MAC_ADDRESS', '$BYTES_IN', '$BYTES_OUT', '$SESSION_TIME', '$NAS_IP', NOW());
" 