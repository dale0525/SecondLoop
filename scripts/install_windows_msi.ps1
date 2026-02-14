param(
  [Parameter(Mandatory = $true)]
  [string]$MsiPath,

  [switch]$Quiet,
  [switch]$LaunchAfterInstall,
  [string]$InstallDirName = 'SecondLoop',
  [string]$ExecutableName = 'secondloop.exe',
  [int]$LaunchProbeTimeoutSeconds = 15
)

$ErrorActionPreference = 'Stop'

function Get-ExpectedInstalledExecutablePath {
  param(
    [string]$InstallDir,
    [string]$Executable
  )

  if (-not $env:LOCALAPPDATA) {
    return ''
  }

  return Join-Path $env:LOCALAPPDATA ("Programs\$InstallDir\$Executable")
}

function Find-InstalledExecutableUnderPrograms {
  param(
    [string]$Executable
  )

  if (-not $env:LOCALAPPDATA) {
    return ''
  }

  $programsRoot = Join-Path $env:LOCALAPPDATA 'Programs'
  if (-not (Test-Path $programsRoot)) {
    return ''
  }

  $candidate = Get-ChildItem -Path $programsRoot -Filter $Executable -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if ($candidate) {
    return $candidate.FullName
  }

  return ''
}

$resolvedMsiPath = ''
try {
  $resolvedMsiPath = (Resolve-Path $MsiPath).Path
} catch {
  throw "MSI package not found: $MsiPath"
}

$arguments = @('/i', "`"$resolvedMsiPath`"")
if ($LaunchAfterInstall) {
  $arguments += 'SECONDLOOP_LAUNCH_AFTER_INSTALL=1'
} else {
  $arguments += 'SECONDLOOP_LAUNCH_AFTER_INSTALL=0'
}
if ($Quiet) {
  $arguments += '/qn'
  $arguments += '/norestart'
}

Write-Host ('Running: msiexec.exe ' + ($arguments -join ' '))
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -PassThru -Wait

if ($process.ExitCode -notin @(0, 1641, 3010)) {
  throw "MSI install failed with exit code $($process.ExitCode)."
}

Write-Host "Installed package: $resolvedMsiPath"

if (-not $LaunchAfterInstall) {
  return
}

if (-not $Quiet) {
  return
}

$timeoutSeconds = [Math]::Max(0, $LaunchProbeTimeoutSeconds)
$expectedExe = Get-ExpectedInstalledExecutablePath -InstallDir $InstallDirName -Executable $ExecutableName
$installedExe = ''

if ($expectedExe) {
  $deadline = (Get-Date).AddSeconds($timeoutSeconds)
  do {
    if (Test-Path $expectedExe) {
      $installedExe = (Resolve-Path $expectedExe).Path
      break
    }

    if ((Get-Date) -ge $deadline) {
      break
    }

    Start-Sleep -Milliseconds 500
  } while ($true)
}

if (-not $installedExe -or -not (Test-Path $installedExe)) {
  $installedExe = Find-InstalledExecutableUnderPrograms -Executable $ExecutableName
}

if (-not $installedExe) {
  if (-not $expectedExe) {
    $expectedExe = "<LOCALAPPDATA unavailable>\\Programs\\$InstallDirName\\$ExecutableName"
  }
  Write-Warning "Installed executable not found after $timeoutSeconds seconds. Expected path: $expectedExe"
  return
}

Start-Process -FilePath $installedExe | Out-Null
Write-Host "Launched app: $installedExe"
