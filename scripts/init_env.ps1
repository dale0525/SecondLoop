$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
$src = Join-Path $repoRootPath '.env.example'
$dst = Join-Path $repoRootPath '.env.local'

if (Test-Path $dst) {
  Write-Host "SecondLoop: $dst already exists."
  exit 0
}

if (-not (Test-Path $src)) {
  Write-Error "SecondLoop: missing $src"
  exit 1
}

Copy-Item -Path $src -Destination $dst
Write-Host "SecondLoop: created $dst. Edit it to configure Cloud keys."
