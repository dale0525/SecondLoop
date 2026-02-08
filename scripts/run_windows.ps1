$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

# Load `.env.local` if present (same format as `.env.example`)
$envFile = Join-Path $repoRootPath '.env.local'
if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { return }

    $name = $parts[0].Trim()
    if ($name.StartsWith('export ')) { $name = $name.Substring(7).Trim() }
    if ($name -eq 'SECONDLOOP_CLOUD_GATEWAY_BASE_URL') {
      throw "SecondLoop: do not set SECONDLOOP_CLOUD_GATEWAY_BASE_URL in .env.local. Use SECONDLOOP_CLOUD_ENV + SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING/PROD instead."
    }

    $value = $parts[1].Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Trim('"') }

    if ($name) { $env:$name = $value }
  }
}

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

Write-Host "Running: prepare_desktop_runtime.dart --platform windows --arch x64"
& dart pub global run fvm:main dart run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Running: flutter run -d windows"
$firebaseWebApiKey = $env:SECONDLOOP_FIREBASE_WEB_API_KEY
$cloudEnv = $env:SECONDLOOP_CLOUD_ENV
$cloudGatewayBaseUrl = $null
if ($cloudEnv) {
  switch ($cloudEnv.ToLowerInvariant()) {
    'staging' { $cloudGatewayBaseUrl = $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'stage' { $cloudGatewayBaseUrl = $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'prod' { $cloudGatewayBaseUrl = $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
    'production' { $cloudGatewayBaseUrl = $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
  }
}

$defines = @()
if ($firebaseWebApiKey) { $defines += "--dart-define=SECONDLOOP_FIREBASE_WEB_API_KEY=$firebaseWebApiKey" }
if ($cloudGatewayBaseUrl) { $defines += "--dart-define=SECONDLOOP_CLOUD_GATEWAY_BASE_URL=$cloudGatewayBaseUrl" }

& dart pub global run fvm:main flutter run -d windows @defines
exit $LASTEXITCODE
