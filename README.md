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

