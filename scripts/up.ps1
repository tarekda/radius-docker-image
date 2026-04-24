param(
  [switch]$Foreground
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker CLI not found. Install Docker Desktop for Windows."
  exit 1
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Get-Item -LiteralPath $scriptDir).Parent.FullName
$composeFile = Join-Path $repoRoot "docker-compose.yml"

Set-Location -LiteralPath $repoRoot

if (-not (Test-Path ".env") -and (Test-Path "env.example")) {
  Copy-Item "env.example" ".env" -Force
  Write-Host "Created .env from env.example (includes COMPOSE_BAKE for compose build on Windows)"
}

# `docker compose` does not always apply COMPOSE_BAKE from .env to the build — set it in this session too
if (Test-Path -LiteralPath ".env") {
  Get-Content -LiteralPath ".env" | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)=') { return }
    $k = $Matches[1]
    if ($k -ne "COMPOSE_BAKE" -and $k -notlike "COMPOSE_*") { return }
    $v = $_.Substring($_.IndexOf('=') + 1).Trim()
    if ($v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
    Set-Item -Path "Env:$k" -Value $v
  }
}
if (-not (Test-Path "Env:COMPOSE_BAKE")) {
  $env:COMPOSE_BAKE = "false"
}

$composeBase = @(
  "--file", $composeFile,
  "--project-directory", $repoRoot
)

# Same as: docker compose build && docker compose up
& docker compose @composeBase build @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Foreground) {
  & docker compose @composeBase up @args
} else {
  & docker compose @composeBase up -d @args
  Write-Host "Started in background. Use .\\scripts\\down.ps1 to stop, or 'docker compose logs -f'."
}
