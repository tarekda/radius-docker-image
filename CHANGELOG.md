# Changelog

All notable changes to the Radius Pro FreeRADIUS Docker image are documented here.

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
