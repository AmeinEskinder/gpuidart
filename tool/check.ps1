param([switch]$Headless)
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    if ($Headless) { & dart run tool/check.dart --headless }
    else { & dart run tool/check.dart }
    if ($LASTEXITCODE -ne 0) { throw 'SDK checks failed' }
} finally { Pop-Location }
