$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

& (Join-Path $PSScriptRoot 'setup_nuget.ps1')

$nugetDir = Join-Path (Join-Path $repoRootPath '.tool') 'nuget'
$nugetExe = Join-Path $nugetDir 'nuget.exe'
if (Test-Path $nugetExe) {
  $env:PATH = "$nugetDir;$env:PATH"
} else {
  Write-Warning "nuget.exe not found at $nugetExe; Flutter may download its own copy."
}

Write-Host "Running: flutter pub get"
& dart pub global run fvm:main flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Running: flutter run -d windows"
& dart pub global run fvm:main flutter run -d windows
exit $LASTEXITCODE
