# Architecture — Radius Pro FreeRADIUS container

## Role

This image runs **FreeRADIUS 3.x** as the network authentication and accounting engine for an ISP billing stack. It does **not** include MySQL, the admin API, or the web UI — those are separate services.

## Data flow

```
  CPE / NAS (Mikrotik, etc.)
        │  RADIUS UDP 1812 (auth), 1813 (acct), 1700 (CoA)
        ▼
  ┌─────────────────────────────┐
  │  freeradius container       │
  │  - sites-available/default  │
  │  - quota / expiry / MAC     │
  │  - CoA to NAS               │
  └─────────────┬───────────────┘
                │  MySQL (rlm_sql + shell scripts)
                ▼
  ┌─────────────────────────────┐
  │  MySQL `radius` schema      │
  │  raduserprofile, radacct,   │
  │  connection_logs, …         │
  └─────────────┬───────────────┘
                │
                ▼
  ┌─────────────────────────────┐
  │  xnet-backend-radius-pro    │
  │  (users, invoices, CoA API) │
  └─────────────────────────────┘
```

## Container startup (`start.sh`)

1. Resolve MySQL password (env → file → Docker secret)
2. Write `/run/freeradius-mysql.cnf` (mode 600) for bootstrap scripts
3. Wait until MySQL accepts connections
4. Apply timezone from `TZ`
5. Run `bootstrap_schema.sh` (idempotent SQL patches)
6. Optional background **daily quota reset** at `DAILY_RESET_AT`
7. Start `freeradius -f -l stdout` (or `-X` if `FREERADIUS_DEBUG=1`)

## Configuration layout

| Path in container | Purpose |
|-------------------|---------|
| `/etc/freeradius/3.0/sites-available/default` | Auth, acct, CoA policy |
| `/etc/freeradius/3.0/mods-enabled/sql` | MySQL connection |
| `/etc/freeradius/3.0/clients.conf` | NAS clients + loopback healthcheck |
| `/opt/freeradius/3.0/scripts/` | Quota reset, CoA helpers, bootstrap |

## Schema ownership

| Source | When |
|--------|------|
| `mysql/init/*.sql` | **Manual** fresh DB install (reference; not started by this compose) |
| `bootstrap_schema.sh` + `patch_*.sql` | **Every container start** (idempotent) |
| Backend TypeORM migrations | Admin API deploys (`xnet-backend-radius-pro`) |
| `mysql/alter_*.sql` | **Manual** one-off DBA scripts |

Keep bootstrap patches and backend migrations aligned when adding columns used by RADIUS policy.

## Deployment topologies

**Standalone (this repo):** RADIUS only → external MySQL.

**Full stack (`deployment/docker-compose.yml`):** Redis, RabbitMQ, RADIUS, backend, frontend on `radiuspro` network; MySQL typically on host via `host.docker.internal`.

## Logging

- **Default:** stdout (container logs / Loki via Docker logging driver)
- **Optional:** `RADIUS_REQUEST_LOG_ENABLED=1` → structured files under `/var/log/freeradius/`
- **Persistence:** bind `./logs` (dev) or named volume `radiuspro_freeradius_logs` (prod)

## Capacity

- Auth listener `max_connections = 128` (parallel in-flight auth requests per socket)
- Scale horizontally only with care: daily reset runs inside each replica unless externalized
