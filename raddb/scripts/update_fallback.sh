#!/bin/bash
# update_fallback.sh: Update raduserprofile for a given username

USERNAME="$1"
# Adjust the following variables to match your MySQL configuration
RADIUS_DB_HOST="host.docker.internal"
DB_USER="radius"
DB_PASS="password"
DB_NAME="radius"

mysql -h "$RADIUS_DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
UPDATE raduserprofile SET is_fallback = 1 WHERE username = '${USERNAME}';
EOF
