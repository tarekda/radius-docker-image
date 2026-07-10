# FreeRADIUS Docker Image (Radius Pro)

FreeRADIUS 3.x container for the Radius Pro ISP stack: quota/FUP, CoA, subscription expiry, MAC binding, and MySQL-backed auth/accounting.

**Image version:** see [`VERSION`](VERSION) and [`CHANGELOG.md`](CHANGELOG.md).

## Quickstart (Windows / Docker Desktop)

Prerequisites: Docker Desktop with Compose v2.

```powershell
Copy-Item env.example .env
# Edit .env — SQL_SERVER and SQL_USER are required; set SQL_PASSWORD (do not commit it).
docker compose up --build
```

Helper scripts:

```powershell
.\scripts\up.ps1          # detached (default)
.\scripts\up.ps1 -Foreground
.\scripts\down.ps1
```

### Production-style standalone (named log volume)

```powershell
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

Full stack (backend + frontend + RADIUS): use [`deployment/docker-compose.yml`](../deployment/docker-compose.yml) in the deployment repo.

## Required environment

| Variable | Description |
|----------|-------------|
| `SQL_SERVER` | MySQL host (required) |
| `SQL_USER` | MySQL user (required) |
| `SQL_PASSWORD` | MySQL password — set in `.env`, never commit |

Optional: `SQL_PASSWORD_FILE` or Docker secret at `/run/secrets/sql_password`. `start.sh` resolves these and **exports `SQL_PASSWORD`** for both bootstrap scripts and FreeRADIUS `rlm_sql`.

## Common settings

| Variable | Default | Notes |
|----------|---------|--------|
| `TZ` | `Asia/Beirut` (compose) / `UTC` (env.example) | Affects daily reset schedule |
| `SQL_PORT` | `3306` | |
| `SQL_DATABASE` | `radius` | |
| `FREERADIUS_DEBUG` | `0` | `1` = verbose `-X` |
| `DAILY_RESET_ENABLED` | `1` | In-container midnight reset job |
| `DAILY_RESET_AT` | `00:00` | Local time (`HH:MM`) |
| `RADIUS_REQUEST_LOG_ENABLED` | `0` | `1` writes `requests.log`, `replies.log`, `accounting.log` under `/var/log/freeradius` for Loki/Promtail |
| `HEALTHCHECK_SECRET` | `radius-healthcheck` | Loopback-only Status-Server client; change in production |

## Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 1812 | UDP | Authentication |
| 1813 | UDP | Accounting |
| 1700 | UDP | CoA / Disconnect |

## Health check

Docker runs `healthcheck.sh`: a **Status-Server** round-trip on `127.0.0.1:1812` (not just `freeradius -C`). Allow ~90s start period for MySQL wait + schema bootstrap.

## Quota cycle & retention

- Monthly quota window: MySQL function `fn_quota_cycle_start(username)` — patched on container start via `bootstrap_schema.sh`.
- Log purge: `sp_purge_old_logs` nightly (see `raddb/scripts/patch_log_retention.sql`).
- Auth listener `max_connections` is **128** (raised from 16 for NAS retry bursts).
- SQL module `pool.max` is **128** (must stay ≥ auth concurrency; was 25 and exhausted on reconnect storms).
- Prometheus metrics on **:9812/metrics** (`RADIUS_METRICS_ENABLED=1`).

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and data flow
- [`docs/RUNBOOK.md`](docs/RUNBOOK.md) — operations, upgrades, troubleshooting

## Building with version labels

```bash
docker build \
  --build-arg IMAGE_VERSION="$(cat VERSION)" \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg VCS_REF="$(git rev-parse --short HEAD)" \
  -t radius-docker-image-freeradius:$(cat VERSION) \
  .
```

## CI

GitHub Actions: ShellCheck on scripts, `docker build`, and `freeradius -C` config validation.
