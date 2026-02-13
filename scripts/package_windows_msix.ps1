$ErrorActionPreference = 'Stop'

param(
  [string]$Version = '',
  [string]$OutputPath = 'dist',
  [string]$OutputName = '',
  [string]$CertificatePath = '',
  [string]$CertificatePassword = '',
  [string]$Publisher = '',
  [switch]$SkipBuild
)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

function Import-DotEnvLocal {
  $envFile = Join-Path $repoRootPath '.env.local'
  if (-not (Test-Path $envFile)) {
    return
  }

  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { return }

    $parts = $line -split '=', 2
    if ($parts.Count -ne 2) { return }

    $name = $parts[0].Trim()
    if ($name.StartsWith('export ')) { $name = $name.Substring(7).Trim() }

    $value = $parts[1].Trim()
    if ($value.StartsWith('"') -and $value.EndsWith('"')) {
      $value = $value.Trim('"')
    }

    if ($name) { $env:$name = $value }
  }
}

function Resolve-CloudGatewayBaseUrl {
  if (-not $env:SECONDLOOP_CLOUD_ENV) {
    return ''
  }

  switch ($env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant()) {
    'staging' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'stage' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_STAGING }
    'prod' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
    'production' { return $env:SECONDLOOP_CLOUD_GATEWAY_BASE_URL_PROD }
    default { return '' }
  }
}

function Build-DartDefines {
  $defines = @()

  if ($env:SECONDLOOP_FIREBASE_WEB_API_KEY) {
    $defines += "--dart-define=SECONDLOOP_FIREBASE_WEB_API_KEY=$($env:SECONDLOOP_FIREBASE_WEB_API_KEY)"
  }

  $cloudGatewayBaseUrl = Resolve-CloudGatewayBaseUrl
  if ($cloudGatewayBaseUrl) {
    $defines += "--dart-define=SECONDLOOP_CLOUD_GATEWAY_BASE_URL=$cloudGatewayBaseUrl"
  }

  if ($env:SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD -and
      $env:SECONDLOOP_CLOUD_ENV -and
      ($env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant() -eq 'prod' -or $env:SECONDLOOP_CLOUD_ENV.ToLowerInvariant() -eq 'production')) {
    $defines += "--dart-define=SECONDLOOP_MANAGED_VAULT_BASE_URL=$($env:SECONDLOOP_MANAGED_VAULT_BASE_URL_PROD)"
  }

  return $defines
}

Import-DotEnvLocal

if (-not $CertificatePath -and $env:SECONDLOOP_WINDOWS_MSIX_CERT_PATH) {
  $CertificatePath = $env:SECONDLOOP_WINDOWS_MSIX_CERT_PATH
}
if (-not $CertificatePassword -and $env:SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD) {
  $CertificatePassword = $env:SECONDLOOP_WINDOWS_MSIX_CERT_PASSWORD
}
if (-not $Publisher -and $env:SECONDLOOP_WINDOWS_MSIX_PUBLISHER) {
  $Publisher = $env:SECONDLOOP_WINDOWS_MSIX_PUBLISHER
}

& (Join-Path $PSScriptRoot 'setup_nuget.ps1')

$nugetDir = Join-Path (Join-Path $repoRootPath '.tool') 'nuget'
$nugetExe = Join-Path $nugetDir 'nuget.exe'
if (Test-Path $nugetExe) {
  $env:PATH = "$nugetDir;$env:PATH"
}

Write-Host 'Running: flutter pub get'
& dart pub global run fvm:main flutter pub get
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Running: prepare_desktop_runtime.dart --platform windows --arch x64'
& dart pub global run fvm:main dart run tools/prepare_desktop_runtime.dart --platform=windows --arch=x64
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host 'Running: sync_desktop_runtime_to_appdir.dart --platform windows'
& dart pub global run fvm:main dart run tools/sync_desktop_runtime_to_appdir.dart --platform=windows
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if (-not $SkipBuild) {
  $buildArgs = @('build', 'windows', '--release')
  $buildArgs += Build-DartDefines
  Write-Host ('Running: flutter ' + ($buildArgs -join ' '))
  & dart pub global run fvm:main flutter @buildArgs
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$msixArgs = @(
  'run',
  'msix:create',
  '--build-windows',
  'false',
  '--output-path',
  $OutputPath,
  '--install-certificate',
  'false'
)

if ($Version) {
  $msixArgs += @('--version', $Version)
}
if ($OutputName) {
  $msixArgs += @('--output-name', $OutputName)
}
if ($Publisher) {
  $msixArgs += @('--publisher', $Publisher)
}
if ($CertificatePath) {
  $msixArgs += @('--certificate-path', $CertificatePath)
}
if ($CertificatePassword) {
  $msixArgs += @('--certificate-password', $CertificatePassword)
}

Write-Host ('Running: dart ' + ($msixArgs -join ' '))
& dart pub global run fvm:main dart @msixArgs
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$latestMsix = Get-ChildItem -Path $OutputPath -Filter '*.msix' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if (-not $latestMsix) {
  throw "MSIX package not found under $OutputPath"
}

if ($CertificatePath -and (Test-Path $CertificatePath)) {
  try {
    if ($CertificatePassword) {
      $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        (Resolve-Path $CertificatePath).Path,
        $CertificatePassword,
        ([System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
      )
    } else {
      $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
        (Resolve-Path $CertificatePath).Path
      )
    }

    $cerPath = Join-Path $latestMsix.DirectoryName ($latestMsix.BaseName + '.cer')
    $cerBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    [System.IO.File]::WriteAllBytes($cerPath, $cerBytes)
    Write-Host "Exported public certificate: $cerPath"
  } catch {
    Write-Warning "Failed to export .cer from $CertificatePath: $_"
  }
}

Write-Host "MSIX package ready: $($latestMsix.FullName)"
