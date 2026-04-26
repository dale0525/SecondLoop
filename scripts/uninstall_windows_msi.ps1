param(
  [string]$ProductName = 'SecondLoop Dev',
  [string]$InstallDirName = 'SecondLoop Dev',
  [string]$ExecutableName = 'secondloop.exe',
  [string]$CompanyName = 'com.secondloop',
  [string]$AppId = '',
  [switch]$Quiet,
  [switch]$KeepUserData,
  [switch]$SkipResidualCleanup
)

$ErrorActionPreference = 'Stop'

function Get-ExpectedInstallLocation {
  param([string]$DirectoryName)

  if (-not $env:LOCALAPPDATA) {
    return ''
  }

  $safeDirectoryName = Get-SafeDirectoryName -Value $DirectoryName
  if ([string]::IsNullOrWhiteSpace($safeDirectoryName)) {
    return ''
  }

  return (Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $safeDirectoryName))
}

function Test-IsPathEqualOrChild {
  param(
    [string]$CandidatePath,
    [string]$ParentPath
  )

  if ([string]::IsNullOrWhiteSpace($CandidatePath) -or
      [string]::IsNullOrWhiteSpace($ParentPath)) {
    return $false
  }

  try {
    $normalizedCandidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd([char[]]@([char]92, [char]47))
    $normalizedParent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd([char[]]@([char]92, [char]47))
  } catch {
    return $false
  }

  if ($normalizedCandidate.Equals($normalizedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $prefix = $normalizedParent + [System.IO.Path]::DirectorySeparatorChar
  return $normalizedCandidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Resolve-SafeInstallLocation {
  param(
    [string]$InstallLocation,
    [string]$ExpectedInstallLocation
  )

  if ([string]::IsNullOrWhiteSpace($InstallLocation)) {
    return $ExpectedInstallLocation
  }

  if (Test-IsPathEqualOrChild -CandidatePath $InstallLocation -ParentPath $ExpectedInstallLocation) {
    return $InstallLocation
  }

  Write-Warning "Ignoring unsafe InstallLocation from registry: $InstallLocation"
  return $ExpectedInstallLocation
}

function Get-DefaultAppId {
  param([string]$ResolvedProductName)

  if ($ResolvedProductName -eq 'SecondLoop Dev') {
    return 'com.secondloop.secondloopdev'
  }

  return 'com.secondloop.secondloop'
}

function Get-EffectiveAppId {
  param(
    [string]$ConfiguredAppId,
    [string]$ResolvedProductName
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredAppId)) {
    return $ConfiguredAppId.Trim()
  }

  return Get-DefaultAppId -ResolvedProductName $ResolvedProductName
}

function Get-SafeDirectoryName {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return ''
  }

  $safeValue = $Value -replace '[<>:"/\\|?*]', '_'
  $safeValue = $safeValue.TrimEnd()
  $safeValue = $safeValue -replace '[.]+$', ''
  if ($safeValue.Length -gt 255) {
    $safeValue = $safeValue.Substring(0, 255)
  }

  return $safeValue
}

function Get-AppStorageRelativePath {
  param(
    [string]$ResolvedProductName,
    [string]$ResolvedCompanyName
  )

  $safeProductName = Get-SafeDirectoryName -Value $ResolvedProductName
  if ([string]::IsNullOrWhiteSpace($safeProductName)) {
    return ''
  }

  $safeCompanyName = Get-SafeDirectoryName -Value $ResolvedCompanyName
  if ($safeCompanyName -eq 'com.secondloop') {
    return (Join-Path 'com.secondloop' $safeProductName)
  }
  if ([string]::IsNullOrWhiteSpace($safeCompanyName)) {
    return $safeProductName
  }

  return (Join-Path $safeCompanyName $safeProductName)
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

function Add-UniquePath {
  param(
    [System.Collections.Generic.List[string]]$Paths,
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  $normalizedPath = Normalize-PathValue $Path
  $alreadyPresent = $Paths | Where-Object { (Normalize-PathValue $_) -eq $normalizedPath } | Select-Object -First 1
  if (-not $alreadyPresent) {
    $Paths.Add($Path) | Out-Null
  }
}

function Get-InstallResidueDirectories {
  param(
    [string]$InstallDirName,
    [string]$ProductName,
    [string]$AppId,
    [string]$InstallLocation,
    [string]$ExpectedInstallLocation
  )

  $directories = New-Object System.Collections.Generic.List[string]

  $safeInstallLocation = Resolve-SafeInstallLocation -InstallLocation $InstallLocation -ExpectedInstallLocation $ExpectedInstallLocation
  Add-UniquePath -Paths $directories -Path $safeInstallLocation

  if ($env:LOCALAPPDATA) {
    $safeInstallDirName = Get-SafeDirectoryName -Value $InstallDirName
    $safeProductName = Get-SafeDirectoryName -Value $ProductName
    $safeAppId = Get-SafeDirectoryName -Value $AppId

    if (-not [string]::IsNullOrWhiteSpace($safeInstallDirName)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:LOCALAPPDATA (Join-Path 'Programs' $safeInstallDirName))
    }
    if (-not [string]::IsNullOrWhiteSpace($safeProductName)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:LOCALAPPDATA $safeProductName)
    }
    if (-not [string]::IsNullOrWhiteSpace($safeAppId)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:LOCALAPPDATA $safeAppId)
    }
  }

  return @($directories)
}

function Get-ShortcutResiduePaths {
  param([string]$ProductName)

  $paths = New-Object System.Collections.Generic.List[string]
  $safeProductName = Get-SafeDirectoryName -Value $ProductName

  if ($env:APPDATA -and -not [string]::IsNullOrWhiteSpace($safeProductName)) {
    Add-UniquePath -Paths $paths -Path (Join-Path $env:APPDATA (Join-Path 'Microsoft\Windows\Start Menu\Programs' $safeProductName))
    Add-UniquePath -Paths $paths -Path (Join-Path $env:APPDATA (Join-Path 'Microsoft\Windows\Start Menu\Programs' "$safeProductName.lnk"))
  }

  $desktopDir = [Environment]::GetFolderPath('DesktopDirectory')
  if (-not [string]::IsNullOrWhiteSpace($desktopDir) -and
      -not [string]::IsNullOrWhiteSpace($safeProductName)) {
    Add-UniquePath -Paths $paths -Path (Join-Path $desktopDir "$safeProductName.lnk")
  }

  return @($paths)
}

function Get-ApplicationDataDirectories {
  param(
    [string]$ProductName,
    [string]$CompanyName,
    [string]$AppId
  )

  $directories = New-Object System.Collections.Generic.List[string]
  $relativeAppPath = Get-AppStorageRelativePath -ResolvedProductName $ProductName -ResolvedCompanyName $CompanyName
  $safeAppId = Get-SafeDirectoryName -Value $AppId

  if ($env:APPDATA) {
    if (-not [string]::IsNullOrWhiteSpace($relativeAppPath)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:APPDATA $relativeAppPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($safeAppId)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:APPDATA $safeAppId)
    }
  }

  return @($directories)
}

function Get-ApplicationCacheDirectories {
  param(
    [string]$ProductName,
    [string]$CompanyName,
    [string]$AppId
  )

  $directories = New-Object System.Collections.Generic.List[string]
  $relativeAppPath = Get-AppStorageRelativePath -ResolvedProductName $ProductName -ResolvedCompanyName $CompanyName
  $safeAppId = Get-SafeDirectoryName -Value $AppId

  if ($env:LOCALAPPDATA) {
    if (-not [string]::IsNullOrWhiteSpace($relativeAppPath)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:LOCALAPPDATA $relativeAppPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($safeAppId)) {
      Add-UniquePath -Paths $directories -Path (Join-Path $env:LOCALAPPDATA $safeAppId)
    }
  }

  return @($directories)
}

function Get-ApplicationStateFiles {
  param([string[]]$AppDataDirectories)

  $stateFiles = New-Object System.Collections.Generic.List[string]
  foreach ($appDataDirectory in $AppDataDirectories) {
    Add-UniquePath -Paths $stateFiles -Path (Join-Path $appDataDirectory 'shared_preferences.json')
    Add-UniquePath -Paths $stateFiles -Path (Join-Path $appDataDirectory 'flutter_secure_storage.dat')
    Add-UniquePath -Paths $stateFiles -Path (Join-Path $appDataDirectory 'secondloop.sqlite3')
    Add-UniquePath -Paths $stateFiles -Path (Join-Path $appDataDirectory 'secondloop.sqlite3-wal')
    Add-UniquePath -Paths $stateFiles -Path (Join-Path $appDataDirectory 'secondloop.sqlite3-shm')
  }

  return @($stateFiles)
}

function Remove-FileSystemTree {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  for ($attempt = 1; $attempt -le 3; $attempt += 1) {
    try {
      if (Test-Path -LiteralPath $Path -PathType Container) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Host "Removed directory: $Path"
        return
      }

      if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        Write-Host "Removed file: $Path"
        return
      }

      return
    } catch {
      if ($attempt -ge 3) {
        Write-Warning "Failed to remove '$Path': $($_.Exception.Message)"
        return
      }

      Start-Sleep -Milliseconds 500
    }
  }
}

function Remove-EmptyDirectoryIfEmpty {
  param(
    [string]$Path,
    [string]$ProtectedRoot
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return
  }

  if (-not [string]::IsNullOrWhiteSpace($ProtectedRoot)) {
    $normalizedPath = Normalize-PathValue $Path
    $normalizedProtectedRoot = Normalize-PathValue $ProtectedRoot
    if ($normalizedPath -eq $normalizedProtectedRoot) {
      return
    }
  }

  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
      return
    }

    $child = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1
    if ($null -ne $child) {
      return
    }

    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
    Write-Host "Removed empty directory: $Path"
  } catch {
    Write-Warning "Failed to remove empty directory '$Path': $($_.Exception.Message)"
  }
}

function Remove-EmptyApplicationDataParents {
  param(
    [string[]]$ApplicationDirectories,
    [string]$RootDirectory
  )

  $parentDirectories = New-Object System.Collections.Generic.List[string]
  foreach ($applicationDirectory in $ApplicationDirectories) {
    if ([string]::IsNullOrWhiteSpace($applicationDirectory)) {
      continue
    }

    try {
      $parentDirectory = [System.IO.Directory]::GetParent([System.IO.Path]::GetFullPath($applicationDirectory))
    } catch {
      continue
    }

    if ($null -eq $parentDirectory) {
      continue
    }

    Add-UniquePath -Paths $parentDirectories -Path $parentDirectory.FullName
  }

  foreach ($parentDirectory in $parentDirectories) {
    Remove-EmptyDirectoryIfEmpty -Path $parentDirectory -ProtectedRoot $RootDirectory
  }
}

function Remove-RegistryTreeIfExists {
  param([string]$RegistryPath)

  if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    return
  }

  try {
    if (Test-Path -Path $RegistryPath) {
      Remove-Item -Path $RegistryPath -Recurse -Force -ErrorAction Stop
      Write-Host "Removed registry key: $RegistryPath"
    }
  } catch {
    Write-Warning "Failed to remove registry key '$RegistryPath': $($_.Exception.Message)"
  }
}

function Test-RegistryTreeHasChildrenOrValues {
  param([string]$RegistryPath)

  if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    return $false
  }

  try {
    if (-not (Test-Path -Path $RegistryPath)) {
      return $false
    }

    $childKey = Get-ChildItem -Path $RegistryPath -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $childKey) {
      return $true
    }

    $item = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue
    if ($null -eq $item) {
      return $false
    }

    $metadataNames = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    $value = $item.PSObject.Properties |
      Where-Object { $metadataNames -notcontains $_.Name } |
      Select-Object -First 1

    return ($null -ne $value)
  } catch {
    return $true
  }
}

function Remove-RegistryTreeIfEmpty {
  param([string]$RegistryPath)

  if ([string]::IsNullOrWhiteSpace($RegistryPath)) {
    return
  }

  if (-not (Test-Path -Path $RegistryPath)) {
    return
  }

  if (Test-RegistryTreeHasChildrenOrValues -RegistryPath $RegistryPath) {
    return
  }

  Remove-RegistryTreeIfExists -RegistryPath $RegistryPath
}

function Test-RegistryEntryHasSafeInstallLocation {
  param(
    [psobject]$Entry,
    [string]$ExpectedInstallLocation
  )

  $installLocation = Get-StringValue $Entry.InstallLocation
  return Test-IsPathEqualOrChild -CandidatePath $installLocation -ParentPath $ExpectedInstallLocation
}

function Test-RegistryEntryMatchesProduct {
  param(
    [psobject]$Entry,
    [string]$ExpectedInstallLocation,
    [string]$ProductCode
  )

  $uninstallString = Get-StringValue $Entry.UninstallString
  $entryProductCode = Resolve-ProductCode -Entry $Entry
  $hasSafeInstallLocation = Test-RegistryEntryHasSafeInstallLocation -Entry $Entry -ExpectedInstallLocation $ExpectedInstallLocation

  if (-not [string]::IsNullOrWhiteSpace($ProductCode)) {
    if ($Entry.PSChildName -eq $ProductCode -or
        $entryProductCode -eq $ProductCode -or
        $uninstallString.IndexOf($ProductCode, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
      return $true
    }
  }

  if ($hasSafeInstallLocation) {
    return $true
  }

  return $false
}

function Remove-ResidualUninstallRegistryEntries {
  param(
    [string]$ExpectedInstallLocation,
    [string]$ProductCode
  )

  Get-UninstallRegistryEntries | Where-Object {
    Test-RegistryEntryMatchesProduct -Entry $_ -ExpectedInstallLocation $ExpectedInstallLocation -ProductCode $ProductCode
  } | ForEach-Object {
    Remove-RegistryTreeIfExists -RegistryPath $_.PSPath
  }
}

function Remove-UninstallResidue {
  param(
    [string]$ProductName,
    [string]$InstallDirName,
    [string]$ExecutableName,
    [string]$CompanyName,
    [string]$AppId,
    [string]$InstallLocation,
    [string]$ProductCode,
    [switch]$KeepUserData
  )

  $effectiveAppId = Get-EffectiveAppId -ConfiguredAppId $AppId -ResolvedProductName $ProductName

  $pathsToRemove = New-Object System.Collections.Generic.List[string]
  $appDataDirectories = @()
  $appCacheDirectories = @()
  foreach ($path in (Get-ShortcutResiduePaths -ProductName $ProductName)) {
    Add-UniquePath -Paths $pathsToRemove -Path $path
  }
  $expectedInstallLocationPath = Get-ExpectedInstallLocation -DirectoryName $InstallDirName
  foreach ($path in (Get-InstallResidueDirectories -InstallDirName $InstallDirName -ProductName $ProductName -AppId $effectiveAppId -InstallLocation $InstallLocation -ExpectedInstallLocation $expectedInstallLocationPath)) {
    Add-UniquePath -Paths $pathsToRemove -Path $path
  }

  if (-not $KeepUserData) {
    $appDataDirectories = @(Get-ApplicationDataDirectories -ProductName $ProductName -CompanyName $CompanyName -AppId $effectiveAppId)
    $appCacheDirectories = @(Get-ApplicationCacheDirectories -ProductName $ProductName -CompanyName $CompanyName -AppId $effectiveAppId)
    foreach ($path in (Get-ApplicationStateFiles -AppDataDirectories $appDataDirectories)) {
      Add-UniquePath -Paths $pathsToRemove -Path $path
    }
    foreach ($path in $appDataDirectories) {
      Add-UniquePath -Paths $pathsToRemove -Path $path
    }
    foreach ($path in $appCacheDirectories) {
      Add-UniquePath -Paths $pathsToRemove -Path $path
    }
  }

  foreach ($path in $pathsToRemove) {
    Remove-FileSystemTree -Path $path
  }

  if (-not $KeepUserData) {
    Remove-EmptyApplicationDataParents -ApplicationDirectories $appDataDirectories -RootDirectory $env:APPDATA
    Remove-EmptyApplicationDataParents -ApplicationDirectories $appCacheDirectories -RootDirectory $env:LOCALAPPDATA
  }

  Remove-ResidualUninstallRegistryEntries -ExpectedInstallLocation $expectedInstallLocationPath -ProductCode $ProductCode

  $safeProductRegistryKeyName = Get-SafeDirectoryName -Value $ProductName
  if (-not [string]::IsNullOrWhiteSpace($safeProductRegistryKeyName)) {
    Remove-RegistryTreeIfExists -RegistryPath "HKCU:\Software\SecondLoop\$safeProductRegistryKeyName"
  }
  Remove-RegistryTreeIfEmpty -RegistryPath 'HKCU:\Software\SecondLoop\Installer'
  Remove-RegistryTreeIfEmpty -RegistryPath 'HKCU:\Software\SecondLoop'
}

$expectedInstallLocationPath = Get-ExpectedInstallLocation -DirectoryName $InstallDirName
$matchingEntries = @(
  Get-UninstallRegistryEntries | Where-Object {
    Test-RegistryEntryMatchesProduct `
      -Entry $_ `
      -ExpectedInstallLocation $expectedInstallLocationPath `
      -ProductCode ''
  }
)

$selectedEntry = $null
$productCode = ''
$selectedInstallLocation = $expectedInstallLocationPath

if ($matchingEntries.Count -gt 0) {
  $selectedEntry = $matchingEntries | Select-Object -First 1
  $productCode = Resolve-ProductCode -Entry $selectedEntry
  $entryInstallLocation = Get-StringValue $selectedEntry.InstallLocation
  if (-not [string]::IsNullOrWhiteSpace($entryInstallLocation)) {
    $selectedInstallLocation = Resolve-SafeInstallLocation -InstallLocation $entryInstallLocation -ExpectedInstallLocation $expectedInstallLocationPath
  }
} else {
  Write-Warning "Installed MSI entry not found for ProductName='$ProductName' InstallDirName='$InstallDirName'. Running residual cleanup only."
}

if ($selectedEntry -and [string]::IsNullOrWhiteSpace($productCode)) {
  throw "Unable to resolve MSI product code for '$ProductName'. UninstallString=$($selectedEntry.UninstallString)"
}

& (Join-Path $PSScriptRoot 'stop_windows_installed_app.ps1') -InstallDirName $InstallDirName -ExecutableName $ExecutableName -TerminateIfNeeded
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

if ($selectedEntry) {
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
}

if (-not $SkipResidualCleanup) {
  $cleanupArgs = @{
    ProductName = $ProductName
    InstallDirName = $InstallDirName
    ExecutableName = $ExecutableName
    CompanyName = $CompanyName
    AppId = $AppId
    InstallLocation = $selectedInstallLocation
    ProductCode = $productCode
  }

  if ($KeepUserData) {
    $cleanupArgs.KeepUserData = $true
  }

  Remove-UninstallResidue @cleanupArgs
}

if ($selectedEntry) {
  Write-Host "Uninstalled package: $ProductName ($productCode)"
} else {
  Write-Host "Residual cleanup completed for missing package: $ProductName"
}
