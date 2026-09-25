$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$setup = Join-Path $PSScriptRoot 'windows/enable_release_checks.ps1'
$directory = Join-Path $projectRoot ('.cache/prerequisite-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
$reportPath = Join-Path $directory 'inspection.json'
'{"passed":false,"error":"preserve the earlier installation failure"}' | Set-Content -LiteralPath $reportPath -Encoding UTF8
$previousHash = (Get-FileHash -LiteralPath $reportPath).Hash
$installedBefore = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'build/windows-prerequisites.json') -ErrorAction SilentlyContinue).Hash
& powershell.exe -NoProfile -File $setup -Sandbox -Japanese -CheckOnly -ReportPath $reportPath
if ($LASTEXITCODE -ne 0) { throw 'Read-only prerequisite inspection failed.' }
$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
if ($report.mode -ne 'inspection' -or $null -ne $report.passed -or @($report.steps).Count -ne 0) {
    throw 'Inspection must not claim an installation pass or run installation steps.'
}
if ((Get-FileHash -LiteralPath $report.previous_report).Hash -ne $previousHash) {
    throw 'The previous failure report was not preserved byte-for-byte.'
}
$pending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
if ($report.restart_needed -ne $pending -or ($pending -and !($report.blockers -match 'Restart Windows'))) {
    throw 'Pending Windows servicing was not reported as requiring restart.'
}
[Windows.Networking.Connectivity.NetworkInformation,Windows,ContentType=WindowsRuntime] | Out-Null
$connection = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
if ($connection) {
    $cost = $connection.GetConnectionCost()
    if (($cost.NetworkCostType -in @('Fixed','Variable') -or $cost.Roaming -or $cost.OverDataLimit) -and !($report.blockers -match 'network cost')) {
        throw 'Metered network was not reported before installation.'
    }
}
$installedAfter = (Get-FileHash -LiteralPath (Join-Path $projectRoot 'build/windows-prerequisites.json') -ErrorAction SilentlyContinue).Hash
if ($installedBefore -ne $installedAfter) { throw 'Inspection changed the installation report.' }
$japaneseReportPath = Join-Path $directory 'japanese-inspection.json'
& powershell.exe -NoProfile -File $setup -Japanese -CheckOnly -ReportPath $japaneseReportPath
if ($LASTEXITCODE -ne 0) { throw 'Japanese-only inspection failed.' }
$japaneseReport = Get-Content -Raw -LiteralPath $japaneseReportPath | ConvertFrom-Json
if ($japaneseReport.mode -ne 'inspection' -or $null -ne $japaneseReport.passed -or @($japaneseReport.steps).Count -ne 0) {
    throw 'Japanese-only inspection must not claim installation or invoke servicing.'
}
if ($japaneseReport.blockers -match 'restart|servicing') {
    throw 'An unrelated pending restart must not preempt the Japanese-only DISM attempt.'
}
if ($pending -and ($japaneseReport.restart_needed -ne $true -or !($japaneseReport.notes -match 'restart'))) {
    throw 'Japanese-only inspection must retain and explain the pending Windows restart.'
}
$result = [ordered]@{
    tested_at_utc = [DateTime]::UtcNow.ToString('o'); passed = $true
    scope = 'Read-only setup inspection and report preservation; no Windows installation or release-gate pass'
    inspection = $report; japanese_only_inspection = $japaneseReport
}
$destination = Join-Path $projectRoot 'reports/mvp/prerequisites/inspection-check.json'
New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $destination -Encoding UTF8
Write-Output 'PASS: pending-restart/network inspection, preserved failure report, no installation result claimed.'
