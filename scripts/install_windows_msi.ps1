param(
  [Parameter(Mandatory = $true)]
  [string]$MsiPath,

  [switch]$Quiet,
  [switch]$LaunchAfterInstall
)

$ErrorActionPreference = 'Stop'

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

$installedExe = Join-Path $env:LOCALAPPDATA 'Programs\SecondLoop\secondloop.exe'
if (-not (Test-Path $installedExe)) {
  Write-Warning "Installed executable not found: $installedExe"
  return
}

Start-Process -FilePath $installedExe | Out-Null
Write-Host "Launched app: $installedExe"
