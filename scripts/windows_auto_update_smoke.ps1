param(
  [string]$OldVersion = '1.0.0+1',
  [string]$NewVersion = '1.0.1+1',
  [string]$PackId = 'com.secondloop.secondloopdev',
  [string]$Channel = 'devwin',
  [string]$ExeName = 'secondloop.exe',
  [int]$Port = 8443,
  [string]$OutputRoot = 'dist/windows-auto-update-smoke',
  [string]$CertificatePemPath = 'dist/auto-update-test/localhost-dev-cert.pem',
  [string]$CertificateKeyPath = 'dist/auto-update-test/localhost-dev-cert.key',
  [switch]$SkipBuild,
  [switch]$SkipCertificateTrust,
  [switch]$LeaveServerRunning
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'use_windows_short_workspace.ps1')

$repoRootPath = Resolve-SecondLoopProjectDir -DefaultRepoRoot (Join-Path $PSScriptRoot '..')
Set-Location $repoRootPath

function Get-VersionName([string]$SemanticVersionWithBuild) {
  return ($SemanticVersionWithBuild -split '\+', 2)[0]
}

function Get-InstalledProcessName {
  return [System.IO.Path]::GetFileNameWithoutExtension($ExeName)
}

function Set-PubspecVersion {
  param(
    [string]$PubspecPath,
    [string]$VersionValue
  )

  $content = Get-Content -LiteralPath $PubspecPath -Raw
  $updated = [System.Text.RegularExpressions.Regex]::Replace(
    $content,
    '(?m)^version:\s*.+$',
    "version: $VersionValue",
    1
  )
  Write-Utf8NoBomFile -Path $PubspecPath -Content $updated
}

function Write-Utf8NoBomFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-PixiPythonPath {
  $pixiPython = Join-Path $repoRootPath '.pixi/envs/default/python.exe'
  if (Test-Path -LiteralPath $pixiPython) {
    return $pixiPython
  }

  $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
  if ($pythonCommand) {
    return $pythonCommand.Source
  }

  throw 'Python is required for the local HTTPS update server. Run `pixi install` first.'
}

function Invoke-CheckedProcess {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$WorkingDirectory = $repoRootPath,
    [string]$FailureMessage = 'Command failed.'
  )

  Write-Host ('Running: ' + $FilePath + ' ' + ($ArgumentList -join ' '))
  $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru -Wait
  if ($process.ExitCode -ne 0) {
    throw "$FailureMessage ExitCode=$($process.ExitCode)"
  }
}

function Start-ObservedProcess {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$WorkingDirectory = $repoRootPath,
    [string]$FailureMessage = 'Command failed to start.',
    [int]$StartupSeconds = 5
  )

  Write-Host ('Running (detached): ' + $FilePath + ' ' + ($ArgumentList -join ' '))
  $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru
  Start-Sleep -Seconds $StartupSeconds
  if ($process.HasExited -and $process.ExitCode -ne 0) {
    throw "$FailureMessage ExitCode=$($process.ExitCode)"
  }
  return $process
}

function Invoke-PackageBuild {
  param(
    [string]$VersionValue,
    [string]$OutputDir
  )

  $packageScript = Join-Path $PSScriptRoot 'package_windows_velopack.ps1'
  $versionName = Get-VersionName $VersionValue

  $env:SECONDLOOP_APP_ID = $PackId
  $env:SECONDLOOP_APP_NAME = 'SecondLoop Dev'
  $env:SECONDLOOP_RELEASE_API_ORIGIN = "https://localhost:$Port"

  $packageArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $packageScript,
    '-Version', $versionName,
    '-OutputPath', $OutputDir,
    '-PackId', $PackId,
    '-Channel', $Channel
  )
  Invoke-CheckedProcess -FilePath 'powershell.exe' -ArgumentList $packageArgs -FailureMessage "Velopack packaging failed for $VersionValue."
}

function Get-ExpectedFullPackageFileName {
  param([string]$VersionValue)

  $versionName = Get-VersionName $VersionValue
  return "$PackId-$versionName-$Channel-full.nupkg"
}

function Get-FullPackage {
  param(
    [string]$OutputDir,
    [string]$ExpectedFileName
  )

  $packagePath = Join-Path $OutputDir $ExpectedFileName
  if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "Missing expected full nupkg under ${OutputDir}: $ExpectedFileName"
  }

  return Get-Item -LiteralPath $packagePath
}

function Get-SetupExecutable {
  param([string]$OutputDir)

  $setupCandidates = @(Get-ChildItem -LiteralPath $OutputDir -Filter '*Setup*.exe' -File)
  if ($setupCandidates.Count -eq 0) {
    throw "Missing setup executable under $OutputDir"
  }
  if ($setupCandidates.Count -gt 1) {
    $candidateNames = $setupCandidates | ForEach-Object { $_.Name }
    throw "Expected exactly one setup executable under $OutputDir but found: $($candidateNames -join ', ')"
  }

  return $setupCandidates[0]
}

function Get-FileSha256Hex {
  param([string]$PathValue)

  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $stream = [System.IO.File]::OpenRead($PathValue)
    try {
      $hashBytes = $sha256.ComputeHash($stream)
    } finally {
      $stream.Dispose()
    }
  } finally {
    $sha256.Dispose()
  }

  return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

function Get-InstallRoot {
  return Join-Path $env:LOCALAPPDATA $PackId
}

function Get-InstalledExePath {
  return Join-Path (Get-InstallRoot) (Join-Path 'current' $ExeName)
}

function Get-UpdateExePath {
  return Join-Path (Get-InstallRoot) 'Update.exe'
}

function Get-InstalledVersion {
  $exePath = Get-InstalledExePath
  if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    return ''
  }

  $versionInfo = (Get-Item -LiteralPath $exePath).VersionInfo
  if (-not [string]::IsNullOrWhiteSpace($versionInfo.ProductVersion)) {
    return $versionInfo.ProductVersion.Trim()
  }
  if (-not [string]::IsNullOrWhiteSpace($versionInfo.FileVersion)) {
    return $versionInfo.FileVersion.Trim()
  }
  return ''
}

function Stop-InstalledSecondLoopProcess {
  $running = @(Get-RunningInstalledProcesses)

  foreach ($process in $running) {
    Write-Host "Stopping installed SecondLoop process PID=$($process.Id)"
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $process.Id -Timeout 10 -ErrorAction SilentlyContinue
  }
}

function Remove-DirectoryWithRetry {
  param(
    [string]$PathValue,
    [int]$MaxAttempts = 5
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt += 1) {
    try {
      Remove-Item -LiteralPath $PathValue -Recurse -Force
      return
    } catch {
      if ($attempt -ge $MaxAttempts) {
        throw
      }
      Start-Sleep -Seconds $attempt
    }
  }
}

function Remove-ExistingInstallRoot {
  $installRoot = Get-InstallRoot
  Stop-InstalledSecondLoopProcess
  if (Test-Path -LiteralPath $installRoot -PathType Container) {
    Write-Host "Removing existing install root: $installRoot"
    Remove-DirectoryWithRetry -PathValue $installRoot
  }
}

function Wait-ForInstalledVersion {
  param(
    [string]$ExpectedVersion,
    [int]$TimeoutSeconds = 90
  )

  $expectedVersionName = Get-VersionName $ExpectedVersion
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $currentVersion = Get-InstalledVersion
    if ($currentVersion -eq $expectedVersionName) {
      return
    }
    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for installed version $expectedVersionName. Current=$(Get-InstalledVersion)"
}

function Wait-ForStagedPackage {
  param(
    [string]$ExpectedFileName,
    [int]$TimeoutSeconds = 120
  )

  $packagesRoot = Join-Path (Get-InstallRoot) 'packages'
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $candidate = Join-Path $packagesRoot $ExpectedFileName
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return Get-Item -LiteralPath $candidate
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for staged package $ExpectedFileName under $packagesRoot"
}

function Wait-ForRunningInstalledProcess {
  param(
    [string]$ExpectedVersion,
    [int]$TimeoutSeconds = 90
  )

  $expectedVersionName = Get-VersionName $ExpectedVersion
  $expectedPath = Get-InstalledExePath
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

  while ((Get-Date) -lt $deadline) {
    $matching = @(Get-RunningInstalledProcesses)

    if ($matching.Count -gt 0 -and (Get-InstalledVersion) -eq $expectedVersionName) {
      Start-Sleep -Seconds 5
      $stableMatching = @(Get-RunningInstalledProcesses)
      if ($stableMatching.Count -gt 0 -and (Get-InstalledVersion) -eq $expectedVersionName) {
        return
      }
    }

    Start-Sleep -Seconds 2
  }

  throw "Timed out waiting for running installed process at $expectedPath with version $expectedVersionName."
}

function Get-RunningInstalledProcesses {
  $expectedPath = Get-InstalledExePath
  if (-not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
    return @()
  }

  $normalizedExpected = [System.IO.Path]::GetFullPath($expectedPath).ToLowerInvariant()
  $processName = Get-InstalledProcessName
  return @(
    Get-Process -Name $processName -ErrorAction SilentlyContinue |
      Where-Object {
        try {
          $_.Path -and ([System.IO.Path]::GetFullPath($_.Path).ToLowerInvariant() -eq $normalizedExpected)
        } catch {
          $false
        }
      }
  )
}

function Get-CertificateThumbprint {
  param([string]$PemPath)

  $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PemPath)
  return $cert.Thumbprint
}

function Test-CertificateTrustedInCurrentUserRoot {
  param([string]$Thumbprint)

  if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
    return $false
  }

  return $null -ne (
    Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
      Where-Object { $_.Thumbprint -eq $Thumbprint } |
      Select-Object -First 1
  )
}

function Ensure-LocalhostCertificateTrusted {
  param([string]$PemPath)

  if ($SkipCertificateTrust) {
    Write-Host 'Skipping localhost certificate trust step.'
    return
  }

  $thumbprint = Get-CertificateThumbprint -PemPath $PemPath
  if (Test-CertificateTrustedInCurrentUserRoot -Thumbprint $thumbprint) {
    Write-Host "Localhost certificate already trusted for current user: $thumbprint"
    return $thumbprint
  }

  Write-Host "Trusting localhost certificate for current user: $PemPath"
  & certutil -user -addstore Root $PemPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to trust localhost certificate: $PemPath"
  }

  if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
    return $thumbprint
  }

  return $null
}

function Remove-TrustedCertificateByThumbprint {
  param([string]$Thumbprint)

  if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
    return
  }

  Write-Host "Removing localhost certificate from current user Root store: $Thumbprint"
  & certutil -user -delstore Root $Thumbprint | Out-Null
}

function Start-UpdateFeedServer {
  param(
    [string]$ServerRoot,
    [string]$CertificatePath,
    [string]$KeyPath,
    [int]$ListenPort,
    [string]$SmokeRoot
  )

  $pythonPath = Get-PixiPythonPath
  $serverScript = Join-Path $repoRootPath 'tools/windows_https_update_server.py'
  $stdoutPath = Join-Path $SmokeRoot 'https-server.out.log'
  $stderrPath = Join-Path $SmokeRoot 'https-server.err.log'

  Write-Host "Starting local HTTPS update server on https://localhost:$ListenPort"
  $process = Start-Process -FilePath $pythonPath -ArgumentList @(
    $serverScript,
    '--root', $ServerRoot,
    '--cert', $CertificatePath,
    '--key', $KeyPath,
    '--port', $ListenPort.ToString()
  ) -WorkingDirectory $repoRootPath -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

  Start-Sleep -Seconds 2
  if ($process.HasExited) {
    throw "HTTPS update server exited early. Check $stdoutPath and $stderrPath"
  }

  return $process
}

function Wait-ForLatestEndpoint {
  param([int]$ListenPort)

  $endpoint = "https://localhost:$ListenPort/api/releases/latest"
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-RestMethod -Uri $endpoint -TimeoutSec 5
      if ($null -ne $response.version) {
        return $response
      }
    } catch {
      Start-Sleep -Seconds 1
    }
  }

  throw "Timed out waiting for $endpoint"
}

$pubspecPath = Join-Path $repoRootPath 'pubspec.yaml'
$originalPubspec = Get-Content -LiteralPath $pubspecPath -Raw
$smokeRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot
} else {
  Join-Path $repoRootPath $OutputRoot
}
$v1Output = Join-Path $smokeRoot 'v1'
$v2Output = Join-Path $smokeRoot 'v2'
$serverRoot = Join-Path $smokeRoot 'server-root'
$downloadsRoot = Join-Path $serverRoot 'downloads'
$certificatePem = if ([System.IO.Path]::IsPathRooted($CertificatePemPath)) { $CertificatePemPath } else { Join-Path $repoRootPath $CertificatePemPath }
$certificateKey = if ([System.IO.Path]::IsPathRooted($CertificateKeyPath)) { $CertificateKeyPath } else { Join-Path $repoRootPath $CertificateKeyPath }

if (-not (Test-Path -LiteralPath $certificatePem -PathType Leaf)) {
  throw "Missing certificate PEM: $certificatePem"
}
if (-not (Test-Path -LiteralPath $certificateKey -PathType Leaf)) {
  throw "Missing certificate key: $certificateKey"
}

$feedProcess = $null
$trustedCertificateThumbprint = $null
$certificateTrustAddedByScript = $false
$originalUpdatePublicKey = $null
$hadOriginalUpdatePublicKey = Test-Path Env:SECONDLOOP_UPDATE_PUBLIC_KEY
$wasCertificateTrustedBefore = $false

try {
  New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null

  if ($hadOriginalUpdatePublicKey) {
    $originalUpdatePublicKey = $env:SECONDLOOP_UPDATE_PUBLIC_KEY
  }
  Remove-Item Env:SECONDLOOP_UPDATE_PUBLIC_KEY -ErrorAction SilentlyContinue

  if (-not $SkipBuild) {
    if (Test-Path -LiteralPath $v1Output) {
      Remove-Item -LiteralPath $v1Output -Recurse -Force
    }
    if (Test-Path -LiteralPath $v2Output) {
      Remove-Item -LiteralPath $v2Output -Recurse -Force
    }

    Set-PubspecVersion -PubspecPath $pubspecPath -VersionValue $OldVersion
    Invoke-PackageBuild -VersionValue $OldVersion -OutputDir $v1Output

    Set-PubspecVersion -PubspecPath $pubspecPath -VersionValue $NewVersion
    Invoke-PackageBuild -VersionValue $NewVersion -OutputDir $v2Output
  } elseif ((-not (Test-Path -LiteralPath $v1Output)) -or (-not (Test-Path -LiteralPath $v2Output))) {
    $v1Output = Join-Path $repoRootPath 'dist/auto-update-test/v1'
    $v2Output = Join-Path $repoRootPath 'dist/auto-update-test/v2'
  }

  Write-Utf8NoBomFile -Path $pubspecPath -Content $originalPubspec

  if (Test-Path -LiteralPath $serverRoot) {
    Remove-Item -LiteralPath $serverRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $downloadsRoot | Out-Null
  Copy-Item -Path (Join-Path $v2Output '*') -Destination $downloadsRoot -Recurse -Force

  $newVersionName = Get-VersionName $NewVersion
  $manifestArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Join-Path $PSScriptRoot 'run_fvm_tool.ps1'),
    'dart',
    'run',
    'tools/generate_update_manifest.dart',
    '--input-dir', $v2Output,
    '--output-dir', $downloadsRoot,
    '--version', $newVersionName,
    '--windows-app-id', $PackId,
    '--windows-channel', $Channel,
    '--base-download-url', "https://localhost:$Port/downloads",
    '--release-page-url', "https://localhost:$Port/releases/$newVersionName"
  )
  Invoke-CheckedProcess -FilePath 'powershell.exe' -ArgumentList $manifestArgs -FailureMessage 'Failed to generate latest.json for smoke feed.'

  $wasCertificateTrustedBefore = Test-CertificateTrustedInCurrentUserRoot -Thumbprint (Get-CertificateThumbprint -PemPath $certificatePem)
  $trustedCertificateThumbprint = Ensure-LocalhostCertificateTrusted -PemPath $certificatePem
  $certificateTrustAddedByScript = -not $wasCertificateTrustedBefore
  $feedProcess = Start-UpdateFeedServer -ServerRoot $serverRoot -CertificatePath $certificatePem -KeyPath $certificateKey -ListenPort $Port -SmokeRoot $smokeRoot

  $latestManifest = Wait-ForLatestEndpoint -ListenPort $Port
  Write-Host "Update feed version: $($latestManifest.version)"

  Remove-ExistingInstallRoot

  $setupExe = Get-SetupExecutable -OutputDir $v1Output

  $expectedPackageFileName = Get-ExpectedFullPackageFileName -VersionValue $NewVersion
  $expectedPackageFile = Get-FullPackage -OutputDir $v2Output -ExpectedFileName $expectedPackageFileName

  $installLog = Join-Path $smokeRoot 'install-v1.log'
  $installArgs = @('--silent', '--log', $installLog)
  Invoke-CheckedProcess -FilePath $setupExe.FullName -ArgumentList $installArgs -FailureMessage 'Initial Velopack installation failed.'

  Wait-ForInstalledVersion -ExpectedVersion $OldVersion
  Write-Host "Installed old version: $(Get-InstalledVersion)"

  $installedExe = Get-InstalledExePath
  $null = Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Path $installedExe -Parent) -PassThru
  Wait-ForRunningInstalledProcess -ExpectedVersion $OldVersion

  $stagedPackage = Wait-ForStagedPackage -ExpectedFileName $expectedPackageFile.Name
  Write-Host "Staged package downloaded from feed: $($stagedPackage.FullName)"

  Stop-InstalledSecondLoopProcess
  Start-Sleep -Seconds 2

  $null = Start-Process -FilePath $installedExe -WorkingDirectory (Split-Path -Path $installedExe -Parent) -PassThru

  Wait-ForInstalledVersion -ExpectedVersion $NewVersion
  Wait-ForRunningInstalledProcess -ExpectedVersion $NewVersion

  Write-Host "Smoke test succeeded. Install root: $(Get-InstallRoot)"
  Write-Host "Final running version: $(Get-InstalledVersion)"
} finally {
  Write-Utf8NoBomFile -Path $pubspecPath -Content $originalPubspec

  if ($hadOriginalUpdatePublicKey) {
    Set-Item -Path Env:SECONDLOOP_UPDATE_PUBLIC_KEY -Value $originalUpdatePublicKey
  } else {
    Remove-Item Env:SECONDLOOP_UPDATE_PUBLIC_KEY -ErrorAction SilentlyContinue
  }

  if ($null -ne $feedProcess -and -not $LeaveServerRunning) {
    Stop-Process -Id $feedProcess.Id -Force -ErrorAction SilentlyContinue
    Wait-Process -Id $feedProcess.Id -Timeout 5 -ErrorAction SilentlyContinue
  }

  if ($null -ne $trustedCertificateThumbprint -and -not $SkipCertificateTrust) {
    if ($certificateTrustAddedByScript) {
      Remove-TrustedCertificateByThumbprint -Thumbprint $trustedCertificateThumbprint
    }
  }
}
