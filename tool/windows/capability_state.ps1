function Get-CapabilityInstallStatus {
    param([object[]]$Capabilities, [bool]$RestartNeeded)
    $states = @($Capabilities | ForEach-Object { [string]$_.State })
    if ($states.Count -eq 0 -or @($states | Where-Object { $_ -notin @('Installed','InstallPending','NotPresent') }).Count -gt 0) {
        return 'incomplete'
    }
    if ($RestartNeeded -or 'InstallPending' -in $states) { return 'restart_required' }
    if (@($states | Where-Object { $_ -ne 'Installed' }).Count -eq 0) { return 'installed' }
    return 'incomplete'
}
