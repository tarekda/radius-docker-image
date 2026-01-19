#!/bin/bash

USERNAME=$1
MAC_ADDRESS=$2
NAS_IP=$3
STATUS=$4
RADIUS_DB_HOST="${SQL_SERVER:-host.docker.internal}"
RADIUS_DB_USER="${SQL_USER:-radius}"
RADIUS_DB_PASSWORD="${SQL_PASSWORD:-password}"
RADIUS_DB_NAME="${SQL_DATABASE:-radius}"
RADIUS_DB_PORT="${SQL_PORT:-3306}"

mysql -h "$RADIUS_DB_HOST" -P "$RADIUS_DB_PORT" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD" -D "$RADIUS_DB_NAME" -e " INSERT INTO connection_logs (username, mac_address, status, ip_address, timestamp) VALUES ('$USERNAME', '$MAC_ADDRESS', '$STATUS', '$NAS_IP', NOW());" 

mysql -h "$RADIUS_DB_HOST" -P "$RADIUS_DB_PORT" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD"  -D "$RADIUS_DB_NAME" -e " SELECT username, account_status FROM raduserprofile WHERE username='$1';" 