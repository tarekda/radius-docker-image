param(
  # Run in foreground (stream logs). Default is detached/background.
  [switch]$Foreground
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker CLI not found. Install Docker Desktop for Windows."
  exit 1
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Test-Path ".env") -and (Test-Path "env.example")) {
  Copy-Item "env.example" ".env" -Force
  Write-Host "Created .env from env.example"
}

if ($Foreground) {
  & docker compose up --build @args
} else {
  & docker compose up --build -d @args
  Write-Host "Started in background (detached). Use .\\scripts\\down.ps1 to stop, or 'docker compose logs -f' to follow logs."
}

