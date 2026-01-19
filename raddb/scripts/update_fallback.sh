#!/bin/bash
# update_fallback.sh: Update raduserprofile for a given username

USERNAME="$1"
RADIUS_DB_HOST="${SQL_SERVER:-host.docker.internal}"
DB_USER="${SQL_USER:-radius}"
DB_PASS="${SQL_PASSWORD:-password}"
DB_NAME="${SQL_DATABASE:-radius}"
DB_PORT="${SQL_PORT:-3306}"

mysql -h "$RADIUS_DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
UPDATE raduserprofile SET is_fallback = 1 WHERE username = '${USERNAME}';
INSERT INTO quota_logs (username, event_type, quota_type, timestamp)
VALUES ('${USERNAME}', 'exceeded', 'daily', NOW());
EOF
