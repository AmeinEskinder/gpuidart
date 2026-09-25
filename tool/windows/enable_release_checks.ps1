param(
    [switch]$Sandbox,
    [switch]$Japanese,
    [switch]$CheckOnly,
    [string]$ReportPath = (Join-Path $PSScriptRoot '../../build/windows-prerequisites.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'capability_state.ps1')
if (!$Sandbox -and !$Japanese) { throw 'Specify -Sandbox, -Japanese, or both. No settings have changed.' }
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$CheckOnly -and !$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as Administrator and run this script. It does not elevate itself or restart Windows.'
}
function Get-ReleaseSetupEnvironment {
    $restartReasons = @()
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path -LiteralPath $key) { $restartReasons += $key }
    }
    $network = [ordered]@{ cost = 'Unknown'; roaming = $false; over_data_limit = $false }
    try {
        [Windows.Networking.Connectivity.NetworkInformation,Windows,ContentType=WindowsRuntime] | Out-Null
        $connection = [Windows.Networking.Connectivity.NetworkInformation]::GetInternetConnectionProfile()
        if ($connection) {
            $cost = $connection.GetConnectionCost()
            $network.cost = [string]$cost.NetworkCostType
            $network.roaming = $cost.Roaming
            $network.over_data_limit = $cost.OverDataLimit
        } else { $network.cost = 'Disconnected' }
    } catch { $network['inspection_error'] = $_.Exception.Message }
    [pscustomobject]@{ restart_pending = $restartReasons.Count -gt 0; restart_reasons = $restartReasons; network = $network }
}

function Assert-DownloadAvailable($environment) {
    if ($environment.network.cost -ne 'Unrestricted' -or $environment.network.roaming -or $environment.network.over_data_limit) {
        throw "Windows download is blocked by this setup check: network cost is $($environment.network.cost). Use an unmetered connection, or turn off Metered connection if you accept the data usage. No network settings were changed."
    }
}

$environmentBefore = Get-ReleaseSetupEnvironment
$report = [ordered]@{
    started_at_utc = [DateTime]::UtcNow.ToString('o'); passed = $false; steps = @()
    mode = 'install'; environment_before = $environmentBefore
    restart_needed = $environmentBefore.restart_pending
}
if ($CheckOnly -and !$PSBoundParameters.ContainsKey('ReportPath')) {
    $ReportPath = Join-Path $PSScriptRoot '../../build/windows-prerequisites.inspection.json'
}
$ReportPath = [IO.Path]::GetFullPath($ReportPath)
New-Item -ItemType Directory -Path (Split-Path $ReportPath -Parent) -Force | Out-Null
if (Test-Path -LiteralPath $ReportPath) {
    $previousPath = $ReportPath + '.' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.json'
    Copy-Item -LiteralPath $ReportPath -Destination $previousPath
    $report['previous_report'] = $previousPath
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
if ($CheckOnly) {
    $report.mode = 'inspection'
    $report.passed = $null
    $report['blockers'] = @()
    $report['notes'] = @()
    if ($environmentBefore.restart_pending) {
        if ($Sandbox) { $report.blockers += 'Restart Windows to complete pending servicing before Sandbox setup.' }
        if ($Japanese) { $report.notes += 'A Windows restart is pending. A Japanese-only installation can ask DISM whether the requested capabilities can be installed now; this inspection cannot establish that outcome.' }
    }
    if ($Japanese) {
        try { Assert-DownloadAvailable $environmentBefore } catch { $report.blockers += $_.Exception.Message }
    }
    $report['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    $report.blockers | ForEach-Object { Write-Output $_ }
    $report.notes | ForEach-Object { Write-Output $_ }
    Write-Output "Inspection only; no installation attempted. Saved $ReportPath"
    return
}
$japaneseCapabilities = @('Language.Basic~~~ja-JP~0.0.1.0','Language.Fonts.Jpan~~~und-JPAN~0.0.1.0')
foreach ($step in @('Sandbox','Japanese')) {
    if (($step -eq 'Sandbox' -and !$Sandbox) -or ($step -eq 'Japanese' -and !$Japanese)) { continue }
    $result = [ordered]@{ name = $step; passed = $false; status = 'failed' }
    try {
        $environment = Get-ReleaseSetupEnvironment
        if ($step -eq 'Sandbox' -and ($environment.restart_pending -or $report.restart_needed)) {
            throw 'Windows has pending servicing. Restart Windows before Sandbox setup, or use -Japanese alone to attempt the independent language installation. Sandbox installation was not attempted.'
        }
        if ($step -eq 'Sandbox') {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM
            $result['previous_state'] = [string]$feature.State
            if ($feature.State -eq 'Enabled') {
                $result['restart_needed'] = $false
            } elseif ($feature.State -eq 'EnablePending') {
                $result['restart_needed'] = $true
            } else {
                $enabled = Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart
                $result['restart_needed'] = [bool]$enabled.RestartNeeded
            }
            $result['state'] = [string](Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM).State
            if ($result.state -notin @('Enabled','EnablePending')) { throw "Sandbox feature state is $($result.state)." }
            $result.restart_needed = $result.restart_needed -or $result.state -eq 'EnablePending'
            $result.status = if ($result.restart_needed) { 'restart_required' } else { 'installed' }
        } else {
            if ($environment.restart_pending) {
                Write-Warning 'Windows has a pending restart. Attempting Japanese capabilities through DISM; Windows may still refuse or report that these capabilities need a restart.'
            }
            $result['capabilities_before'] = @($japaneseCapabilities | ForEach-Object {
                Get-WindowsCapability -Online -Name $_ | Select-Object Name,@{n='State';e={[string]$_.State}}
            })
            $result['restart_needed'] = $false
            foreach ($capability in $result.capabilities_before) {
                if ($capability.State -eq 'Installed') { continue }
                if ($capability.State -eq 'InstallPending') {
                    $result.restart_needed = $true
                    break
                }
                Assert-DownloadAvailable (Get-ReleaseSetupEnvironment)
                Write-Output "Installing $($capability.Name). Windows Update may take several minutes."
                $installed = Add-WindowsCapability -Online -Name $capability.Name
                if ($installed.RestartNeeded) {
                    $result.restart_needed = $true
                    break
                }
            }
            $result['capabilities_after'] = @($japaneseCapabilities | ForEach-Object {
                Get-WindowsCapability -Online -Name $_ | Select-Object Name,@{n='State';e={[string]$_.State}}
            })
            $result.status = Get-CapabilityInstallStatus -Capabilities $result.capabilities_after -RestartNeeded $result.restart_needed
            if ($result.status -eq 'restart_required') { $result.restart_needed = $true }
            if ($result.status -eq 'incomplete') {
                throw 'Japanese typing or fonts are not installed yet. See capability states in the report.'
            }
            $result['next_step'] = if ($result.status -eq 'restart_required') {
                'Windows staged installation and requires a restart. Rerun -Japanese after restarting to finish any remaining capabilities. Repeating before restarting will not reinstall the pending capability.'
            } else { 'Add Japanese to the original user language list. Windows display language is unchanged.' }
        }
        $result.passed = $result.status -eq 'installed'
    } catch {
        $result.status = 'failed'
        $result['error'] = $_.Exception.Message
        if ($step -eq 'Japanese' -and $result.Contains('capabilities_before')) {
            try {
                $result['capabilities_after'] = @($japaneseCapabilities | ForEach-Object {
                    Get-WindowsCapability -Online -Name $_ | Select-Object Name,@{n='State';e={[string]$_.State}}
                })
            } catch { $result['inspection_error'] = $_.Exception.Message }
        }
        if ($result.error -match '800f0908|-2146498296') {
            $result['next_step'] = 'Windows refused a metered-network download. Use an unmetered connection before retrying.'
        }
        Write-Warning "$step failed: $($result.error)"
    }
    if ($result['restart_needed']) { $report.restart_needed = $true }
    if ($result.passed) { Write-Output "$step installation checked." }
    if ($result.status -eq 'restart_required') { Write-Warning "$step installation is awaiting a Windows restart. Progress is saved in the capability states." }
    $report.steps += $result
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
$report['environment_after'] = Get-ReleaseSetupEnvironment
$report.restart_needed = $report.restart_needed -or $report.environment_after.restart_pending
$report['installation_passed'] = @($report.steps | Where-Object { !$_.passed }).Count -eq 0
$report.passed = $report.installation_passed -and !$report.restart_needed
$failedSteps = @($report.steps | Where-Object status -eq 'failed')
$report['status'] = if ($failedSteps.Count) { 'failed' } elseif ($report.restart_needed) { 'restart_required' } else { 'installed' }
$report['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output "Saved $ReportPath. No restart was initiated."
if ($report.restart_needed) { Write-Warning 'Windows still reports pending servicing. See the per-step status and capability states in the report.' }
if ($failedSteps.Count) {
    $failures = @($failedSteps | ForEach-Object { "$($_.name): $($_.error)" })
    throw ($failures -join [Environment]::NewLine)
}
if ($report.installation_passed) {
    Write-Output 'Requested components are installed. Installation success and pending restart status are recorded separately; release verification remains pending.'
} else {
    Write-Output 'Installation progress saved. Windows requires a restart before setup can finish; release verification remains pending.'
}
