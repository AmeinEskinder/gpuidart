param(
    [switch]$Sandbox,
    [switch]$Japanese,
    [string]$ReportPath = (Join-Path $PSScriptRoot '../../build/windows-prerequisites.json')
)
$ErrorActionPreference = 'Stop'
if (!$Sandbox -and !$Japanese) { throw 'Specify -Sandbox, -Japanese, or both. No settings have changed.' }
$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as Administrator and run this script. It does not elevate itself or restart Windows.'
}
$report = [ordered]@{ started_at_utc = [DateTime]::UtcNow.ToString('o'); passed = $false; steps = @() }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)
New-Item -ItemType Directory -Path (Split-Path $ReportPath -Parent) -Force | Out-Null
$report | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
foreach ($step in @('Sandbox','Japanese')) {
    if (($step -eq 'Sandbox' -and !$Sandbox) -or ($step -eq 'Japanese' -and !$Japanese)) { continue }
    $result = [ordered]@{ name = $step; passed = $false }
    try {
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
        } else {
            $language = Get-InstalledLanguage -Language ja-JP
            if (!$language -or [string]$language.LanguageFeatures -notmatch 'BasicTyping') {
                Install-Language -Language ja-JP | Out-Null
            }
            $language = Get-InstalledLanguage -Language ja-JP
            if (!$language -or [string]$language.LanguageFeatures -notmatch 'BasicTyping') { throw 'Japanese BasicTyping is not installed.' }
            $result['installed'] = $language | Select-Object LanguageId,LanguagePacks,LanguageFeatures
            $result['next_step'] = 'Sign in again if required, then add Japanese to the original user language list. Windows display language is unchanged.'
        }
        $result.passed = $true
    } catch { $result['error'] = $_.Exception.Message }
    $report.steps += $result
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
$report.passed = @($report.steps | Where-Object { !$_.passed }).Count -eq 0
$report['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Output "Saved $ReportPath. No restart was initiated."
if (!$report.passed) { throw 'One or more prerequisites failed. Read the report before retrying.' }
