# Changelog

All notable changes to the Radius Pro FreeRADIUS Docker image are documented here.

## [5.1.0] - 2026-07-10

### Added
- Prometheus metrics exporter on `:9812/metrics` (Status-Server probe → `freeradius_*` counters); enable with `RADIUS_METRICS_ENABLED=1` (default)

## [5.0.1] - 2026-07-10

### Fixed
- SQL connection pool exhausted under auth bursts (`Cannot open new connection, already at max`): replaced ineffective `max_connections = 25` with FreeRADIUS 3.0 `pool { max = 128 }` aligned to the auth listener

## [5.0.0] - 2026-06-27

### Added
- OCI image labels and semver tagging (`VERSION` file)
- `.dockerignore` for faster, cleaner builds
- `docs/RUNBOOK.md` and `docs/ARCHITECTURE.md`
- `docker-compose.prod.yml` overlay (named log volume)
- CI: `freeradius -C` config validation after image build
- Deployment stack healthcheck parity with standalone compose

### Changed
- Auth listener `max_connections` increased from 16 to 128 (NAS retry bursts)
- Standalone compose: `DAILY_RESET_AT` now read from environment (was hardcoded)
- README aligned with required env vars and logging options
- Pinned `ubuntu:22.04` base image by digest for reproducible builds
- Removed misleading unused `CMD` in Dockerfile (entrypoint owns startup)

### Security / ops
- Document production use of `HEALTHCHECK_SECRET` and `SQL_PASSWORD` (never commit secrets)
- Deployment compose passes `HEALTHCHECK_SECRET` and optional structured request logs
- `start.sh` exports resolved MySQL password for `rlm_sql` (file/secret sources work end-to-end)
