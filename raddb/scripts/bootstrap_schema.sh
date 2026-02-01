#!/bin/bash
# bootstrap_schema.sh: create missing tables on existing deployments.
#
# Why:
# - MySQL docker init scripts under mysql/init only run on first DB initialization.
# - If you already had a database, new tables like `user_default_profiles` won't exist.
# - FreeRADIUS quota logic relies on it (default/original plan tracking).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/lib.sh"

echo "[bootstrap] Ensuring schema objects exist..."

# Keep this idempotent and safe. Avoid FK creation here (can fail on drifted schemas).
mysql_exec "
CREATE TABLE IF NOT EXISTS user_default_profiles (
  username VARCHAR(64) NOT NULL,
  default_profile_id INT NOT NULL,
  PRIMARY KEY (username),
  INDEX idx_udp_default_profile_id (default_profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
" || true

echo "[bootstrap] Done."

