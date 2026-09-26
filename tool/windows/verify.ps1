param(
    [string]$ReportPath = (Join-Path $PSScriptRoot 'verification.json'),
    [ValidateSet('development_machine','clean_vm','clean_machine')]
    [string]$Environment = 'development_machine'
)
$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    tested_at_utc = [DateTime]::UtcNow.ToString('o'); passed = $false
    environment_declared_by_operator = $Environment; package_path = $PSScriptRoot
}
$report | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
try {
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
foreach ($file in $manifest.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file.name)).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "Package hash mismatch: $($file.name)"
    }
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PackageWindow {
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr window);
    [DllImport("user32.dll")] static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    public static bool PerMonitorV2(IntPtr window) {
        return AreDpiAwarenessContextsEqual(GetWindowDpiAwarenessContext(window), new IntPtr(-4));
    }
}
'@
$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = Join-Path $PSScriptRoot $manifest.executable
$start.Arguments = '--self-test'
$start.WorkingDirectory = $env:SystemRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false, $true)
$start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false, $true)
$start.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
foreach ($key in @($start.EnvironmentVariables.Keys)) {
    if ($key -match '^(DART|FLUTTER|GPUIDART|CARGO|RUSTUP)') { $start.EnvironmentVariables.Remove($key) }
}
$process = [Diagnostics.Process]::Start($start)
try {
    $output = $process.StandardOutput.ReadToEndAsync()
    $errors = $process.StandardError.ReadToEndAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    $modules = @()
    $dpi = 0
    $perMonitorV2 = $false
    while (!$process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        $process.Refresh()
        $modules = @($process.Modules | ForEach-Object FileName)
        if ($process.MainWindowHandle -ne [IntPtr]::Zero) {
            $dpi = [PackageWindow]::GetDpiForWindow($process.MainWindowHandle)
            $perMonitorV2 = [PackageWindow]::PerMonitorV2($process.MainWindowHandle)
            if ($modules | Where-Object { $_ -match '\\WinSxS\\.*\\comctl32\.dll$' }) { break }
        }
        Start-Sleep -Milliseconds 20
    }
    if (!$process.WaitForExit(30000)) { throw 'Packaged self-test timed out' }
    if ($process.ExitCode -ne 0) { throw "Packaged self-test failed: $($errors.Result) $($output.Result)" }
    if (!$perMonitorV2 -or $dpi -eq 0) { throw 'Window did not report PerMonitorV2 DPI awareness' }
    foreach ($name in @('gpuidart.dll','vcruntime140.dll')) {
        if ((Join-Path $PSScriptRoot $name) -notin $modules) { throw "Sibling $name was not loaded" }
    }
    if (!($modules | Where-Object { $_ -match '\\WinSxS\\.*\\comctl32\.dll$' })) { throw 'Common Controls v6 was not loaded' }
    if ($modules | Where-Object { $_ -match '\\(dart-sdk|flutter)\\' }) { throw 'An SDK module was loaded' }
    $application = $output.Result.Trim() | ConvertFrom-Json
    $report['application'] = $application
    $report['stderr'] = $errors.Result
    if ($application.mode -cne 'aot' -or $application.passed -isnot [bool] -or !$application.passed) {
        throw 'Application self-test must report mode aot and boolean passed true'
    }
    $report = [ordered]@{
        tested_at_utc = [DateTime]::UtcNow.ToString('o'); passed = $true
        environment_declared_by_operator = $Environment
        os = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture)
        package_path = $PSScriptRoot; working_directory = $start.WorkingDirectory
        path = $start.EnvironmentVariables['PATH']; window_dpi = $dpi; per_monitor_v2 = $perMonitorV2
        build = $manifest.build; native_abi = $manifest.native_abi
        files = $manifest.files; loaded_modules = $modules; application = $application; stderr = $errors.Result
        limitation = 'Machine cleanliness requires an independently provisioned machine or VM; this script verifies launch, application checks, loaded modules and DPI.'
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Output "PASS: packaged self-test, sibling DLLs, Common Controls v6 and PerMonitorV2 at DPI $dpi. Report: $ReportPath"
} finally {
    if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $process.Dispose()
}
} catch {
    $report.passed = $false
    $report['error'] = $_.Exception.Message
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    throw
}
