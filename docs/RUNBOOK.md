# Runbook — Radius Pro FreeRADIUS container

## Normal operations

### Start / stop (standalone)

```powershell
docker compose up -d --build
docker compose down
```

Production overlay (named log volume):

```powershell
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

### Full stack

From `deployment/`:

```powershell
docker compose up -d --build
```

### Check health

```powershell
docker inspect --format='{{.State.Health.Status}}' <container_name>
```

Healthy = Status-Server probe succeeded on loopback. Unhealthy after 90s start period usually means MySQL unreachable or FreeRADIUS failed to bind ports.

### View logs

```powershell
docker logs -f radiuspro-freeradius
# or standalone service name from docker compose ps
```

Enable file logs for Loki: set `RADIUS_REQUEST_LOG_ENABLED=1` and scrape `/var/log/freeradius/*.log` from the volume.

---

## NAS onboarding

1. Add NAS in admin UI (`nas` table) **or** ensure `read_clients = yes` in SQL module loads clients from DB.
2. Open UDP **1812, 1813, 1700** from NAS IP to the RADIUS host.
3. Match **shared secret** exactly between NAS and `nas` table / `clients.conf`.
4. Test with `radclient` from a trusted host (not required in production).

Do **not** rely on commented examples in `clients.conf` for production secrets.

---

## Upgrading the image

1. Read [`CHANGELOG.md`](../CHANGELOG.md) for policy or bootstrap changes.
2. Build new tag: `docker compose build --no-cache` or pull if using a registry.
3. Restart during low-traffic window (active sessions may drop on container replace).
4. Watch logs for bootstrap warnings (`fn_quota_cycle_start`, procedure patches).
5. Verify healthcheck turns **healthy** within ~2 minutes.

Rollback: run previous image tag (e.g. `radiuspro-freeradius:4.x.x`).

---

## Troubleshooting

| Symptom | Likely cause | Action |
|---------|----------------|--------|
| Container exits on start | Missing `SQL_SERVER` / `SQL_USER` / password | Check env; test `mysql` from host |
| Stuck **starting** health | MySQL slow or bootstrap slow | Increase `start_period`; check DB connectivity |
| Auth works, acct missing | NAS not sending accounting | Enable acct on NAS; check 1813/udp |
| Quota not resetting | Wrong `TZ` or `DAILY_RESET_AT` | Set `TZ`; confirm cron loop in logs |
| CoA disconnect fails | `proxy.conf` NAS IP/secret mismatch | Align with real NAS IP and secret |
| High reject rate | Wrong secret, expired user, quota | Use backend auth failure logs / connection_logs |

### Config syntax check (offline)

`freeradius -C` loads the SQL module and may require a reachable MySQL server on some builds. For a quick offline check:

```bash
docker run --rm --entrypoint /usr/sbin/freeradius radius-docker-image-freeradius:5.0.0 -v
```

With MySQL available, pass `SQL_*` and `HEALTHCHECK_SECRET` env vars and run `-C`.

### Manual healthcheck

```bash
docker exec <container> /opt/freeradius/3.0/scripts/healthcheck.sh
echo $?
```

---

## Security checklist (production)

- [ ] Strong unique `SQL_PASSWORD`; not in git
- [ ] Rotate `HEALTHCHECK_SECRET` from default (loopback-only, but good hygiene)
- [ ] No `FREERADIUS_DEBUG=1` in production
- [ ] Do not apply `mysql/init/03-seed.sql` on production databases
- [ ] Restrict who can reach UDP 1812/1813/1700 (ISP core / NAS IPs only)

---

## When to escalate

- Repeated bootstrap failures for stored procedures (DB permissions / binlog)
- MySQL connection pool exhaustion on RADIUS host
- Need for **multiple RADIUS replicas** (daily reset and CoA require design change)

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for component boundaries and schema ownership.
