param(
  [Parameter(Mandatory = $true)]
  [string]$MsiPath,

  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-MsiProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Database,

    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $escapedName = $Name.Replace("'", "''")
  $view = $Database.OpenView("SELECT `Value` FROM `Property` WHERE `Property`='$escapedName'")
  $null = $view.Execute()
  $record = $view.Fetch()
  if ($null -eq $record) {
    return ''
  }

  $rawValue = $record.StringData(1) | Select-Object -Last 1
  if ($null -eq $rawValue) {
    return ''
  }

  return [string]$rawValue
}

$resolvedMsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
if (-not $OutputPath) {
  $msiDir = Split-Path -Parent $resolvedMsiPath
  $msiStem = [System.IO.Path]::GetFileNameWithoutExtension($resolvedMsiPath)
  $OutputPath = Join-Path $msiDir ($msiStem + '.metadata.json')
}

$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $resolvedOutputPath
if ($outputDir) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($resolvedMsiPath, 0))

$metadata = [ordered]@{
  packageName = Get-MsiProperty -Database $database -Name 'ProductName'
  publisher = Get-MsiProperty -Database $database -Name 'Manufacturer'
  productCode = Get-MsiProperty -Database $database -Name 'ProductCode'
  upgradeCode = Get-MsiProperty -Database $database -Name 'UpgradeCode'
  packageVersion = Get-MsiProperty -Database $database -Name 'ProductVersion'
  installerType = 'msi'
}

$json = $metadata | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText($resolvedOutputPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Output $resolvedOutputPath
