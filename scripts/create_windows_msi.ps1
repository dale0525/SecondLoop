param(
  [Parameter(Mandatory = $true)]
  [string]$SourceDir,

  [string]$Version = '1.0.0',
  [string]$OutputPath = 'dist',
  [string]$OutputName = 'secondloop-windows-x64',
  [string]$ProductName = 'SecondLoop',
  [string]$Manufacturer = 'SecondLoop Contributors',
  [string]$UpgradeCode = '8B5A0942-79D3-4B5A-A4E5-3FB906DA63A1',
  [string]$IconPath = 'windows/runner/resources/app_icon.ico',
  [switch]$KeepIntermediate,
  [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$repoRootPath = $repoRoot.Path
Set-Location $repoRootPath

function Convert-ToMsiVersion([string]$RawVersion) {
  if (-not $RawVersion) {
    return '1.0.0'
  }

  $parts = $RawVersion.Trim().Split('.')
  if ($parts.Count -lt 3) {
    throw "MSI version must contain at least 3 dot-separated numeric parts (e.g. 1.2.3). Got: $RawVersion"
  }

  try {
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $build = [int]$parts[2]
  } catch {
    throw "MSI version parts must be numeric. Got: $RawVersion"
  }

  if ($parts.Count -gt 3) {
    Write-Warning "MSI supports 3-part versions. Ignoring extra parts from '$RawVersion'."
  }

  if ($major -lt 0 -or $major -gt 255) {
    throw "MSI major version out of range (0..255): $major"
  }
  if ($minor -lt 0 -or $minor -gt 255) {
    throw "MSI minor version out of range (0..255): $minor"
  }
  if ($build -lt 0 -or $build -gt 65535) {
    throw "MSI build version out of range (0..65535): $build"
  }

  return "$major.$minor.$build"
}

function Escape-Xml([string]$Value) {
  if ($null -eq $Value) {
    return ''
  }
  return [System.Security.SecurityElement]::Escape($Value)
}

function Resolve-Tool([string]$Name) {
  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($null -eq $command) {
    return ''
  }
  return $command.Source
}

function Add-WixBinsToPath {
  $candidateBins = @()

  if ($env:WIX) {
    $candidateBins += $env:WIX
    $candidateBins += (Join-Path $env:WIX 'bin')
  }
  if ($env:WixToolPath) {
    $candidateBins += $env:WixToolPath
    $candidateBins += (Join-Path $env:WixToolPath 'bin')
  }

  $portableCurrent = Join-Path (Join-Path $repoRootPath '.tool') 'wix3\current'
  $candidateBins += $portableCurrent
  $candidateBins += (Join-Path $portableCurrent 'bin')

  $programFilesX86 = ${env:ProgramFiles(x86)}
  if ($programFilesX86) {
    $candidateBins += (Join-Path $programFilesX86 'WiX Toolset v3.11\bin')
    $candidateBins += (Join-Path $programFilesX86 'WiX Toolset v3.14\bin')
  }

  $pathEntries = @()
  if ($env:PATH) {
    $pathEntries = $env:PATH -split ';'
  }

  foreach ($bin in $candidateBins) {
    if (-not (Test-Path $bin)) {
      continue
    }
    $alreadyPresent = $pathEntries | Where-Object { $_ -and $_.TrimEnd('\') -ieq $bin.TrimEnd('\') } | Select-Object -First 1
    if (-not $alreadyPresent) {
      $env:PATH = "$bin;$env:PATH"
      $pathEntries = $env:PATH -split ';'
    }
  }
}

function Ensure-WixToolset {
  $setupScript = Join-Path $PSScriptRoot 'setup_wix.ps1'
  if (-not (Test-Path $setupScript)) {
    throw "WiX Toolset setup script is missing: $setupScript"
  }

  Write-Host 'Ensuring portable WiX Toolset v3 via setup_wix.ps1...'
  & $setupScript
  if (-not $?) {
    throw 'setup_wix.ps1 execution failed.'
  }

  Add-WixBinsToPath
  $tools = @{
    Heat = Resolve-Tool 'heat.exe'
    Candle = Resolve-Tool 'candle.exe'
    Light = Resolve-Tool 'light.exe'
  }

  if (-not ($tools.Heat -and $tools.Candle -and $tools.Light)) {
    throw 'WiX Toolset setup completed but heat/candle/light are still unavailable in PATH.'
  }

  return $tools
}

function Test-IsPathEqualOrChild {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,
    [Parameter(Mandatory = $true)]
    [string]$ParentPath
  )

  $normalizedCandidate = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd('\', '/')
  $normalizedParent = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\', '/')

  if ($normalizedCandidate.Equals($normalizedParent, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $prefix = $normalizedParent + [System.IO.Path]::DirectorySeparatorChar
  return $normalizedCandidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-ValidSourceDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ResolvedSourceDir
  )

  $distPath = Join-Path $repoRootPath 'dist'
  if (-not (Test-Path $distPath)) {
    return
  }

  $resolvedDistPath = (Resolve-Path $distPath).Path
  if (Test-IsPathEqualOrChild -CandidatePath $ResolvedSourceDir -ParentPath $resolvedDistPath) {
    throw "SourceDir points to dist output. Use build/windows/x64/runner/Release as SourceDir."
  }
}

function Save-XmlDocument {
  param(
    [Parameter(Mandatory = $true)]
    [xml]$Document,
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Indent = $true
  $settings.OmitXmlDeclaration = $false
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

  $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
  try {
    $Document.Save($writer)
  } finally {
    $writer.Dispose()
  }
}

function Convert-HarvestToPerUserCompliant {
  param(
    [Parameter(Mandatory = $true)]
    [string]$HarvestPath
  )

  if (-not (Test-Path $HarvestPath)) {
    throw "Harvest manifest not found: $HarvestPath"
  }

  [xml]$harvestDoc = Get-Content -Path $HarvestPath -Raw
  $wixNamespace = 'http://schemas.microsoft.com/wix/2006/wi'
  $nsManager = New-Object System.Xml.XmlNamespaceManager($harvestDoc.NameTable)
  $nsManager.AddNamespace('wix', $wixNamespace)

  $componentNodes = $harvestDoc.SelectNodes("//wix:DirectoryRef[@Id='INSTALLFOLDER']//wix:Component", $nsManager)
  if ($null -eq $componentNodes -or $componentNodes.Count -eq 0) {
    throw "No components were harvested under INSTALLFOLDER in: $HarvestPath"
  }

  $componentRegistryKey = 'Software\SecondLoop\Installer\Components'
  foreach ($componentNode in $componentNodes) {
    $componentId = $componentNode.GetAttribute('Id')
    if (-not $componentId) {
      continue
    }

    $fileNodes = $componentNode.SelectNodes('wix:File', $nsManager)
    if ($null -eq $fileNodes -or $fileNodes.Count -eq 0) {
      continue
    }

    foreach ($fileNode in $fileNodes) {
      $fileNode.SetAttribute('KeyPath', 'no')
    }

    $registryNode = $componentNode.SelectSingleNode("wix:RegistryValue[@Root='HKCU' and @Name='$componentId' and @KeyPath='yes']", $nsManager)
    if (-not $registryNode) {
      $registryNode = $harvestDoc.CreateElement('RegistryValue', $wixNamespace)
      $registryNode.SetAttribute('Root', 'HKCU')
      $registryNode.SetAttribute('Key', $componentRegistryKey)
      $registryNode.SetAttribute('Name', $componentId)
      $registryNode.SetAttribute('Type', 'integer')
      $registryNode.SetAttribute('Value', '1')
      $registryNode.SetAttribute('KeyPath', 'yes')
      $componentNode.AppendChild($registryNode) | Out-Null
    }

  }

  $cleanupComponentId = 'cmpProgramsDirCleanup'
  $cleanupComponent = $harvestDoc.SelectSingleNode("//wix:Component[@Id='$cleanupComponentId']", $nsManager)
  if (-not $cleanupComponent) {
    $installDirectoryRef = $harvestDoc.SelectSingleNode("//wix:DirectoryRef[@Id='INSTALLFOLDER']", $nsManager)
    if (-not $installDirectoryRef) {
      throw "INSTALLFOLDER DirectoryRef was not found in: $HarvestPath"
    }

    $cleanupComponent = $harvestDoc.CreateElement('Component', $wixNamespace)
    $cleanupComponent.SetAttribute('Id', $cleanupComponentId)
    $cleanupComponent.SetAttribute('Guid', '*')

    $installDirectoryRef.AppendChild($cleanupComponent) | Out-Null

    $componentGroup = $harvestDoc.SelectSingleNode("//wix:ComponentGroup[@Id='AppFiles']", $nsManager)
    if (-not $componentGroup) {
      throw "AppFiles ComponentGroup was not found in: $HarvestPath"
    }

    $componentRef = $harvestDoc.CreateElement('ComponentRef', $wixNamespace)
    $componentRef.SetAttribute('Id', $cleanupComponentId)
    $componentGroup.AppendChild($componentRef) | Out-Null
  }

  $cleanupRegistry = $cleanupComponent.SelectSingleNode("wix:RegistryValue[@Root='HKCU' and @Name='ProgramsDirCleanup' and @KeyPath='yes']", $nsManager)
  if (-not $cleanupRegistry) {
    $cleanupRegistry = $harvestDoc.CreateElement('RegistryValue', $wixNamespace)
    $cleanupRegistry.SetAttribute('Root', 'HKCU')
    $cleanupRegistry.SetAttribute('Key', 'Software\SecondLoop\Installer')
    $cleanupRegistry.SetAttribute('Name', 'ProgramsDirCleanup')
    $cleanupRegistry.SetAttribute('Type', 'integer')
    $cleanupRegistry.SetAttribute('Value', '1')
    $cleanupRegistry.SetAttribute('KeyPath', 'yes')
    $cleanupComponent.AppendChild($cleanupRegistry) | Out-Null
  }

  $directoryIds = New-Object System.Collections.Generic.List[string]
  $directoryIds.Add('ProgramsDir')
  $directoryIds.Add('INSTALLFOLDER')
  $harvestedDirectoryNodes = $harvestDoc.SelectNodes("//wix:DirectoryRef[@Id='INSTALLFOLDER']//wix:Directory[@Id]", $nsManager)
  foreach ($directoryNode in $harvestedDirectoryNodes) {
    $directoryId = $directoryNode.GetAttribute('Id')
    if ($directoryId -and -not $directoryIds.Contains($directoryId)) {
      $directoryIds.Add($directoryId)
    }
  }

  $nextRemovalIndex = 1
  foreach ($directoryId in $directoryIds) {
    $existingRemoval = $cleanupComponent.SelectSingleNode("wix:RemoveFolder[@Directory='$directoryId']", $nsManager)
    if ($existingRemoval) {
      continue
    }

    $candidateRemovalId = ("rmfDir{0:D4}" -f $nextRemovalIndex)
    while ($cleanupComponent.SelectSingleNode("wix:RemoveFolder[@Id='$candidateRemovalId']", $nsManager)) {
      $nextRemovalIndex += 1
      $candidateRemovalId = ("rmfDir{0:D4}" -f $nextRemovalIndex)
    }

    $removeDirectory = $harvestDoc.CreateElement('RemoveFolder', $wixNamespace)
    $removeDirectory.SetAttribute('Id', $candidateRemovalId)
    $removeDirectory.SetAttribute('Directory', $directoryId)
    $removeDirectory.SetAttribute('On', 'uninstall')
    $cleanupComponent.AppendChild($removeDirectory) | Out-Null
    $nextRemovalIndex += 1
  }

  Save-XmlDocument -Document $harvestDoc -Path $HarvestPath
}

$resolvedSourceDir = ''
try {
  $resolvedSourceDir = (Resolve-Path $SourceDir).Path
} catch {
  throw "Source directory not found: $SourceDir"
}
Assert-ValidSourceDirectory -ResolvedSourceDir $resolvedSourceDir

$resolvedIconPath = ''
try {
  $resolvedIconPath = (Resolve-Path $IconPath).Path
} catch {
  throw "Icon file not found: $IconPath"
}

$msiVersion = Convert-ToMsiVersion $Version
$toolPaths = Ensure-WixToolset

if (-not $OutputName) {
  $OutputName = 'secondloop-windows-x64'
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$msiPath = Join-Path $OutputPath ($OutputName + '.msi')
$wixTempRoot = Join-Path (Join-Path $repoRootPath '.tool') 'wix-temp'
$workDir = Join-Path $wixTempRoot ([System.Guid]::NewGuid().ToString('N'))
$wixObjDir = Join-Path $workDir 'obj'
$mainWxsPath = Join-Path $workDir 'product.wxs'
$harvestWxsPath = Join-Path $workDir 'harvest.wxs'

New-Item -ItemType Directory -Force -Path $workDir | Out-Null
New-Item -ItemType Directory -Force -Path $wixObjDir | Out-Null

$installDirName = $ProductName
$shortcutRegKey = 'Software\SecondLoop'

$mainWxsContent = @'
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi" xmlns:util="http://schemas.microsoft.com/wix/UtilExtension">
  <Product Id="*" Name="__PRODUCT_NAME__" Language="1033" Version="$(var.ProductVersion)" Manufacturer="__MANUFACTURER__" UpgradeCode="__UPGRADE_CODE__">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perUser" Platform="x64" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <Icon Id="AppIcon" SourceFile="$(var.IconPath)" />
    <Property Id="ARPPRODUCTICON" Value="AppIcon" />
    <Property Id="SECONDLOOP_LAUNCH_AFTER_INSTALL" Value="1" />
    <util:CloseApplication Id="CloseSecondLoopOnUninstall" Target="secondloop.exe" CloseMessage="yes" RebootPrompt="no" TerminateProcess="0" Timeout="5">REMOVE~="ALL"</util:CloseApplication>
    <CustomAction Id="SetLaunchApplicationTarget" Property="WixShellExecTarget" Value="[INSTALLFOLDER]secondloop.exe" />
    <CustomAction Id="LaunchApplication" BinaryKey="WixCA" DllEntry="WixShellExec" Return="check" Impersonate="yes" />
    <InstallExecuteSequence>
      <Custom Action="SetLaunchApplicationTarget" After="InstallFinalize">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 3</Custom>
      <Custom Action="LaunchApplication" After="SetLaunchApplicationTarget">SECONDLOOP_LAUNCH_AFTER_INSTALL = "1" AND NOT Installed AND UILevel >= 3</Custom>
    </InstallExecuteSequence>
    <Feature Id="MainFeature" Title="__PRODUCT_NAME__" Level="1">
      <ComponentGroupRef Id="AppFiles" />
      <ComponentRef Id="StartMenuShortcutComponent" />
    </Feature>
  </Product>

  <Fragment>
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="LocalAppDataFolder">
        <Directory Id="ProgramsDir" Name="Programs">
          <Directory Id="INSTALLFOLDER" Name="__INSTALL_DIR_NAME__" />
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ProgramMenuDir" Name="__PRODUCT_NAME__" />
      </Directory>
    </Directory>
  </Fragment>

  <Fragment>
    <DirectoryRef Id="ProgramMenuDir">
      <Component Id="StartMenuShortcutComponent" Guid="*">
        <Shortcut
          Id="StartMenuShortcut"
          Name="__PRODUCT_NAME__"
          Description="__PRODUCT_NAME__"
          Target="[INSTALLFOLDER]secondloop.exe"
          WorkingDirectory="INSTALLFOLDER" />
        <RemoveFolder Id="ProgramMenuDir" On="uninstall" />
        <RegistryValue Root="HKCU" Key="__SHORTCUT_REG_KEY__" Name="installed" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>
  </Fragment>
</Wix>
'@

$mainWxsContent = $mainWxsContent.Replace('__PRODUCT_NAME__', (Escape-Xml $ProductName))
$mainWxsContent = $mainWxsContent.Replace('__MANUFACTURER__', (Escape-Xml $Manufacturer))
$mainWxsContent = $mainWxsContent.Replace('__UPGRADE_CODE__', (Escape-Xml $UpgradeCode))
$mainWxsContent = $mainWxsContent.Replace('__INSTALL_DIR_NAME__', (Escape-Xml $installDirName))
$mainWxsContent = $mainWxsContent.Replace('__SHORTCUT_REG_KEY__', (Escape-Xml $shortcutRegKey))

Set-Content -Path $mainWxsPath -Value $mainWxsContent -Encoding UTF8

$heatArgs = @(
  'dir',
  $resolvedSourceDir,
  '-nologo',
  '-gg',
  '-scom',
  '-sreg',
  '-sfrag',
  '-srd',
  '-dr',
  'INSTALLFOLDER',
  '-cg',
  'AppFiles',
  '-var',
  'var.SourceDir',
  '-out',
  $harvestWxsPath
)

Write-Host ('Running: ' + $toolPaths.Heat + ' ' + ($heatArgs -join ' '))
& $toolPaths.Heat @heatArgs
if ($LASTEXITCODE -ne 0) {
  throw "heat.exe failed with exit code $LASTEXITCODE"
}

Convert-HarvestToPerUserCompliant -HarvestPath $harvestWxsPath

$wixObjOutDir = [System.IO.Path]::GetFullPath($wixObjDir) + [System.IO.Path]::DirectorySeparatorChar

$candleArgs = @(
  '-nologo',
  "-dSourceDir=$resolvedSourceDir",
  "-dProductVersion=$msiVersion",
  "-dIconPath=$resolvedIconPath",
  '-ext',
  'WixUtilExtension',
  '-out',
  $wixObjOutDir,
  $mainWxsPath,
  $harvestWxsPath
)

Write-Host ('Running: ' + $toolPaths.Candle + ' ' + ($candleArgs -join ' '))
& $toolPaths.Candle @candleArgs
if ($LASTEXITCODE -ne 0) {
  throw "candle.exe failed with exit code $LASTEXITCODE"
}

$mainWixObjPath = Join-Path $wixObjDir 'product.wixobj'
$harvestWixObjPath = Join-Path $wixObjDir 'harvest.wixobj'

$lightArgs = @(
  '-nologo',
  # ICE60/ICE91 are expected for per-user app-local assets (fonts and user-profile
  # directories). Keep strict validation for ICE38/ICE64 while suppressing only
  # these non-blocking checks to keep release logs actionable.
  '-sice:ICE60',
  '-sice:ICE91',
  '-ext',
  'WixUtilExtension',
  '-out',
  $msiPath,
  $mainWixObjPath,
  $harvestWixObjPath
)

Write-Host ('Running: ' + $toolPaths.Light + ' ' + ($lightArgs -join ' '))
& $toolPaths.Light @lightArgs
if ($LASTEXITCODE -ne 0) {
  throw "light.exe failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $msiPath)) {
  throw "MSI package not found: $msiPath"
}

if (-not $KeepIntermediate) {
  Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "MSI package ready: $msiPath"
if ($PassThru) {
  Write-Output $msiPath
}
