param(
  [string]$ProductName = 'SecondLoop Dev',
  [string]$InstallDirName = 'SecondLoop Dev',
  [string]$ExecutableName = 'secondloop.exe',
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Get-ExpectedInstallLocation {
  param([string]$DirectoryName)

  if (-not $env:LOCALAPPDATA) {
    return ''
  }

  return (Join-Path $env:LOCALAPPDATA ("Programs\$DirectoryName"))
}

function Normalize-PathValue {
  param([string]$PathValue)

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return ''
  }

  return $PathValue.Trim().TrimEnd([char[]]@([char]92, [char]47)).ToLowerInvariant()
}

function Get-StringValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return ''
  }

  return [string]$Value
}

function Get-UninstallRegistryEntries {
  $registryRoots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
  )

  foreach ($registryRoot in $registryRoots) {
    if (-not (Test-Path $registryRoot)) {
      continue
    }

    Get-ChildItem -Path $registryRoot -ErrorAction SilentlyContinue | ForEach-Object {
      Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
    }
  }
}

function Resolve-ProductCode {
  param([psobject]$Entry)

  if ($Entry.PSChildName -match '^\{[0-9A-Fa-f\-]+\}$') {
    return $Entry.PSChildName
  }

  $uninstallString = Get-StringValue $Entry.UninstallString
  if ($uninstallString -match '\{[0-9A-Fa-f\-]+\}') {
    return $Matches[0]
  }

  return ''
}

$expectedInstallLocation = Normalize-PathValue (Get-ExpectedInstallLocation -DirectoryName $InstallDirName)

$matchingEntries = @(
  Get-UninstallRegistryEntries | Where-Object {
    $displayName = Get-StringValue $_.DisplayName
    $installLocation = Normalize-PathValue (Get-StringValue $_.InstallLocation)

    $displayName -eq $ProductName -or (
      $expectedInstallLocation -and
      $installLocation -eq $expectedInstallLocation
    )
  }
)

if ($matchingEntries.Count -eq 0) {
  throw "Installed MSI entry not found for ProductName='$ProductName' InstallDirName='$InstallDirName'."
}

$selectedEntry = $matchingEntries | Select-Object -First 1
$productCode = Resolve-ProductCode -Entry $selectedEntry
if ([string]::IsNullOrWhiteSpace($productCode)) {
  throw "Unable to resolve MSI product code for '$ProductName'. UninstallString=$($selectedEntry.UninstallString)"
}

& (Join-Path $PSScriptRoot 'stop_windows_installed_app.ps1') -InstallDirName $InstallDirName -ExecutableName $ExecutableName -TerminateIfNeeded
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

$arguments = @('/x', $productCode)
if ($Quiet) {
  $arguments += '/qn'
  $arguments += '/norestart'
}

Write-Host ('Running: msiexec.exe ' + ($arguments -join ' '))
$process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -PassThru -Wait
if ($process.ExitCode -notin @(0, 1605, 1614, 1641, 3010)) {
  throw "MSI uninstall failed with exit code $($process.ExitCode)."
}

Write-Host "Uninstalled package: $ProductName ($productCode)"
