#!/bin/bash

USERNAME="$1"
MAC_ADDRESS="$2"

# Option 1: Use the special host.docker.internal domain
RADIUS_DB_HOST="host.docker.internal"
RADIUS_DB_USER="radius"
RADIUS_DB_PASSWORD="password"
RADIUS_DB_NAME="radius"

mysql -h "$RADIUS_DB_HOST" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD" "$RADIUS_DB_NAME" -e "INSERT INTO user_mac (username, mac_address) VALUES ('$USERNAME', '$MAC_ADDRESS');"

