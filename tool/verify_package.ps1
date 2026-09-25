param([string]$Zip = 'build/gpuidart-windows-x64.zip')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archive = if ([IO.Path]::IsPathRooted($Zip)) { $Zip } else { Join-Path $projectRoot $Zip }
$outside = Join-Path ([IO.Path]::GetTempPath()) ('gpuidart-package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outside | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath $outside
$reportDirectory = Join-Path $projectRoot 'reports/sdk'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
& powershell -NoProfile -File (Join-Path $outside 'verify.ps1') -ReportPath (Join-Path $reportDirectory 'package.json') -Environment development_machine
if ($LASTEXITCODE -ne 0) { throw 'Extracted package verification failed' }
Write-Output "Retained test package: $outside"
