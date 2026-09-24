$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$reportDirectory = Join-Path $projectRoot 'reports'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$outside = Join-Path ([IO.Path]::GetTempPath()) ('gpuidart-package-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outside | Out-Null
$workingDirectory = Join-Path $outside 'unrelated-working-directory'
New-Item -ItemType Directory -Path $workingDirectory | Out-Null
Expand-Archive -LiteralPath (Join-Path $projectRoot 'build/gpuidart-windows-x64.zip') -DestinationPath $outside
$manifest = Get-Content -LiteralPath "$outside/manifest.json" -Raw | ConvertFrom-Json
foreach ($file in $manifest.files) {
    $copied = Join-Path $outside $file.name
    if ((Get-FileHash -LiteralPath $copied).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Hash mismatch: $($file.name)" }
}
$results = @()
foreach ($mode in @('--self-test', '--measure')) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $outside 'gpuidart.exe'
    $start.Arguments = $mode
    $start.WorkingDirectory = $workingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.EnvironmentVariables['PATH'] = "$env:SystemRoot\System32;$env:SystemRoot"
    foreach ($key in @($start.EnvironmentVariables.Keys)) {
        if ($key -match '^(DART|FLUTTER|GPUIDART|CARGO|RUSTUP)') { $start.EnvironmentVariables.Remove($key) }
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $modules = @()
        $deadline = [DateTime]::UtcNow.AddSeconds(10)
        while (!$process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            $process.Refresh()
            $modules = @($process.Modules | ForEach-Object { $_.FileName })
            if ($modules | Where-Object { $_ -match '\\WinSxS\\.*\\comctl32\.dll$' }) { break }
            Start-Sleep -Milliseconds 50
        }
        if (!$process.WaitForExit(30000)) { throw 'Packaged application timed out' }
        $output = $outputTask.Result
        $errors = $errorTask.Result
        if ($process.ExitCode -ne 0) { throw "Packaged application failed ($($process.ExitCode)): $errors $output" }
        if (!($modules | Where-Object { $_ -match '\\WinSxS\\.*\\comctl32\.dll$' })) { throw 'Common Controls v6 was not observed' }
        if (!($modules | Where-Object { $_ -eq (Join-Path $outside 'gpuidart.dll') })) { throw 'Sibling native DLL was not loaded' }
        if (!($modules | Where-Object { $_ -eq (Join-Path $outside 'vcruntime140.dll') })) { throw 'Packaged CRT was not loaded' }
        if ($modules | Where-Object { $_.StartsWith($projectRoot, [StringComparison]::OrdinalIgnoreCase) -or $_ -match '\\(dart-sdk|flutter)\\' }) { throw 'Application loaded a repository or SDK module' }
        $measurement = $output.Trim() | ConvertFrom-Json
        if ($measurement.mode -ne 'aot') { throw 'Expected the packaged AOT application' }
        $name = if ($mode -eq '--measure') { 'aot-measurement.json' } else { 'aot-self-test.json' }
        $measurement | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $reportDirectory $name) -Encoding UTF8
        $results += [ordered]@{mode=$mode; exit_code=$process.ExitCode; modules=$modules; stderr=$errors}
    } finally {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}
[ordered]@{
    tested_at_utc=[DateTime]::UtcNow.ToString('o'); outside_repository=$outside; unrelated_working_directory=$workingDirectory
    path="$env:SystemRoot\System32;$env:SystemRoot"; runs=$results; files=$manifest.files
    zip_bytes=(Get-Item -LiteralPath (Join-Path $projectRoot 'build/gpuidart-windows-x64.zip')).Length
    limitation='SDK remains installed on this machine; this is an isolated environment/module audit, not a clean VM test.'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$reportDirectory/package.json" -Encoding UTF8
Write-Output "PASS: AOT package launched twice outside the repository with an isolated PATH. Reports: $reportDirectory"
Write-Output "Retained test package: $outside"
