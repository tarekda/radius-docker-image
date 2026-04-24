Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host "Docker CLI not found."
  exit 1
}

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = (Get-Item -LiteralPath $scriptDir).Parent.FullName
$composeFile = Join-Path $repoRoot "docker-compose.yml"

Set-Location -LiteralPath $repoRoot

& docker compose --file $composeFile --project-directory $repoRoot down @args
