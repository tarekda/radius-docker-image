# FreeRADIUS Docker Image (Radius Pro)

FreeRADIUS container used by the Radius Pro stack.

## Windows 11 (Docker Desktop) quickstart

Prereqs:
- Docker Desktop (Compose v2)

Run:

```powershell
Copy-Item env.example .env
docker compose up --build
```

Or with the helper scripts:

```powershell
.\scripts\up.ps1
```

By default, `.\scripts\up.ps1` runs in the background (detached). To run in the foreground:

```powershell
.\scripts\up.ps1 -Foreground
```

Stop:

```powershell
.\scripts\down.ps1
```

## Default settings (preserved)

If you do nothing, compose defaults are:
- `SQL_SERVER=172.8.16.4`
- `SQL_USER=radius`
- `SQL_PASSWORD=password`
- `SQL_PORT=3306`
- `SQL_DATABASE=radius`
- `DAILY_RESET_ENABLED=1`
- `DAILY_RESET_AT=00:00`
- `HEALTHCHECK_SECRET=radius-healthcheck` (loopback-only Status-Server probe used by the Docker healthcheck)

## Quota cycle & retention

- The monthly quota window is computed by the MySQL function `fn_quota_cycle_start(username)`
  (manual anchor `quota_cycle_start_date` wins; otherwise `quota_reset_day` clamped to the
  month length). It is (re)applied on every container start by
  `raddb/scripts/patch_quota_cycle.sql`. Monthly-exceeded users are restored on **their**
  cycle boundary, not globally on day 1.
- If the MySQL server has binary logging enabled, set `log_bin_trust_function_creators=1`
  (already in `mysql/conf.d/my.cnf`) so the non-SUPER radius user can create the function.
- Log tables are purged nightly at 03:30 by `sp_purge_old_logs` (snapshots 30d,
  detailed_usage/connection_logs 90d, quota_logs 365d) — see
  `raddb/scripts/patch_log_retention.sql`.

