#!/bin/bash
set -euo pipefail

MYSQL_DEFAULTS_FILE="${MYSQL_DEFAULTS_FILE:-/run/freeradius-mysql.cnf}"

read_secret_file() {
  local path="$1"
  if [ -f "$path" ]; then
    # shellcheck disable=SC2002
    cat "$path" | tr -d '\r\n'
  fi
}

resolve_mysql_password() {
  # Priority:
  # 1) SQL_PASSWORD (explicit env)
  # 2) SQL_PASSWORD_FILE (path to secret)
  # 3) /run/secrets/sql_password (Docker secret convention)
  if [ -n "${SQL_PASSWORD:-}" ]; then
    echo "$SQL_PASSWORD"
    return 0
  fi
  if [ -n "${SQL_PASSWORD_FILE:-}" ]; then
    read_secret_file "$SQL_PASSWORD_FILE" && return 0
  fi
  read_secret_file "/run/secrets/sql_password" && return 0
  return 1
}

write_mysql_defaults() {
  local host="${SQL_SERVER:-}"
  local port="${SQL_PORT:-3306}"
  local user="${SQL_USER:-}"
  local db="${SQL_DATABASE:-radius}"
  local pass
  pass="$(resolve_mysql_password)" || pass=""

  if [ -z "$host" ] || [ -z "$user" ] || [ -z "$pass" ]; then
    echo "FATAL: missing MySQL credentials. Provide SQL_SERVER, SQL_USER and SQL_PASSWORD (or SQL_PASSWORD_FILE / Docker secret)." >&2
    exit 1
  fi

  umask 077
  cat > "$MYSQL_DEFAULTS_FILE" <<EOF
[client]
host=${host}
port=${port}
user=${user}
password=${pass}
database=${db}
protocol=tcp
EOF
  chmod 600 "$MYSQL_DEFAULTS_FILE" || true
}

write_mysql_defaults

# Allow FreeRADIUS exec scripts (run as freerad) to read DB creds.
chown freerad:freerad "$MYSQL_DEFAULTS_FILE" >/dev/null 2>&1 || true
chmod 600 "$MYSQL_DEFAULTS_FILE" >/dev/null 2>&1 || true

# Wait for MySQL to be ready (no password on argv)
until mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -e "SELECT 1;" >/dev/null 2>&1; do
  echo "Waiting for MySQL to be ready..."
  sleep 1
done

echo "MySQL is ready"

# Apply container timezone if available (requires tzdata in image).
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime || true
  echo "${TZ}" > /etc/timezone || true
fi

# Ensure scripts are executable (Windows hosts may strip +x during build/copy).
chmod +x /opt/freeradius/3.0/scripts/*.sh >/dev/null 2>&1 || true

# Ensure new schema objects exist on existing DBs (idempotent).
/opt/freeradius/3.0/scripts/bootstrap_schema.sh || true

# If we missed midnight while the container was down/restarting, clear stale DAILY fallback flags
# without wiping today's usage.
/opt/freeradius/3.0/scripts/clear_stale_daily_fallback.sh || true

# Run a daily reset at 00:00 (container local time).
# - Resets daily usage rows for today to 0
# - Clears daily fallback flag (is_fallback)
# - Clears monthly exceeded for users whose quota_reset_day is today
#
# Control via env:
#   DAILY_RESET_ENABLED=1|0 (default 1)
#   DAILY_RESET_AT=HH:MM (default 00:00)
if [ "${DAILY_RESET_ENABLED:-1}" = "1" ]; then
  (
    set -euo pipefail
    AT="${DAILY_RESET_AT:-00:00}"
    echo "Daily reset enabled at ${AT} (TZ=${TZ:-system})"

    while true; do
      now="$(date +%s)"
      # Today's scheduled timestamp
      target="$(date -d "$(date +%F) ${AT}:00" +%s 2>/dev/null || true)"
      if [ -z "${target}" ]; then
        # Fallback parsing (some date versions accept HH:MM without seconds)
        target="$(date -d "$(date +%F) ${AT}" +%s)"
      fi
      if [ "${target}" -le "${now}" ]; then
        target="$(date -d "tomorrow ${AT}:00" +%s 2>/dev/null || date -d "tomorrow ${AT}" +%s)"
      fi

      sleep_for=$(( target - now ))
      echo "Next daily reset in ${sleep_for}s (at $(date -d "@${target}" -Is))"
      sleep "${sleep_for}"

      /opt/freeradius/3.0/scripts/reset_daily_quota_all.sh || true

      # Prevent double-run in case of clock drift / DST jumps
      sleep 60
    done
  ) &
fi

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