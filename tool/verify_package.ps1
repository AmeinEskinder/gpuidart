param(
    [string]$Zip = 'build/gpuidart-windows-x64.zip',
    [string]$ReportPath = 'reports/sdk/package.json'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archive = if ([IO.Path]::IsPathRooted($Zip)) { $Zip } else { Join-Path $projectRoot $Zip }
$outside = Join-Path ([IO.Path]::GetTempPath()) ('GPUI Dart package ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outside | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $outside
$report = if ([IO.Path]::IsPathRooted($ReportPath)) { $ReportPath } else { Join-Path $projectRoot $ReportPath }
$reportDirectory = Split-Path $report -Parent
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
& powershell -NoProfile -File (Join-Path $outside 'verify.ps1') -ReportPath $report -Environment development_machine
if ($LASTEXITCODE -ne 0) { throw 'Extracted package verification failed' }
Write-Output "Retained test package: $outside"
