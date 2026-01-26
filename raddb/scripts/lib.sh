#!/bin/bash
# Shared helpers for FreeRADIUS exec scripts (production-safe).
# - Avoids putting DB passwords in process list (uses mysql defaults file)
# - Provides basic SQL escaping for untrusted inputs (username, MAC, IP, etc.)

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

ensure_mysql_defaults() {
  if [ -f "$MYSQL_DEFAULTS_FILE" ]; then
    return 0
  fi

  local host="${SQL_SERVER:-}"
  local port="${SQL_PORT:-3306}"
  local user="${SQL_USER:-}"
  local db="${SQL_DATABASE:-radius}"
  local pass
  pass="$(resolve_mysql_password)" || pass=""

  if [ -z "$host" ] || [ -z "$user" ] || [ -z "$pass" ]; then
    echo "Missing MySQL credentials (SQL_SERVER/SQL_USER/SQL_PASSWORD or secret file)." >&2
    exit 0
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

mysql_exec() {
  ensure_mysql_defaults
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -e "$1" 2>/dev/null
}

mysql_one() {
  ensure_mysql_defaults
  mysql --defaults-extra-file="$MYSQL_DEFAULTS_FILE" -N -s -e "$1" 2>/dev/null || true
}

sql_escape() {
  # Escape a value for inclusion inside single quotes in SQL.
  # This is a minimal defense for scripts; prefer parameterized queries in application code.
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\'/\\\'}"
  printf "%s" "$s"
}

