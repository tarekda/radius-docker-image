#!/bin/bash

USERNAME=$1
RADIUS_DB_HOST="${SQL_SERVER:-host.docker.internal}"
RADIUS_DB_USER="${SQL_USER:-radius}"
RADIUS_DB_PASSWORD="${SQL_PASSWORD:-password}"
RADIUS_DB_NAME="${SQL_DATABASE:-radius}"
RADIUS_DB_PORT="${SQL_PORT:-3306}"

mysql -h "$RADIUS_DB_HOST" -P "$RADIUS_DB_PORT" -u "$RADIUS_DB_USER" -p"$RADIUS_DB_PASSWORD" -D "$RADIUS_DB_NAME" -e "
    UPDATE raduserprofile 
    SET is_monthly_exceeded = 0,
        profile_id = (SELECT default_profile_id FROM user_default_profiles WHERE username = '$USERNAME')
    WHERE username = '$USERNAME' AND is_monthly_exceeded = 1;
" 