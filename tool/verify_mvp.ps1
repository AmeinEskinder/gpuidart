param([ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name = 'WatchlistMvp')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $sourceStatus = @(git status --porcelain --untracked-files=normal -- lib native example tool test pubspec.yaml pubspec.lock Cargo.toml Cargo.lock)
    if ($LASTEXITCODE -ne 0 -or $sourceStatus.Count) {
        throw 'Commit the MVP source and test changes before running release acceptance.'
    }
    $reportDirectory = Join-Path $projectRoot 'reports/mvp'
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    $reportPath = Join-Path $reportDirectory 'acceptance.json'
    $report = [ordered]@{
        started_at_utc=[DateTime]::UtcNow.ToString('o'); source_commit=(git rev-parse HEAD).Trim()
        local_acceptance_passed=$false; release_status='candidate_pending_external_checks'
        external_checks=[ordered]@{clean_windows_launch='pending'; human_ime='pending'; mixed_monitor_dpi='pending'}
        checks=@()
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    $probe = Join-Path $projectRoot '.cache/mvp-dart-executable.dart'
    New-Item -ItemType Directory -Path (Split-Path $probe -Parent) -Force | Out-Null
    "import 'dart:io'; void main() => stdout.write(Platform.resolvedExecutable);" | Set-Content -LiteralPath $probe -Encoding UTF8
    $dart = ((& dart $probe) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $dart -PathType Leaf)) {
        throw 'Could not resolve the Dart executable behind the current launcher.'
    }
    $powershell = Join-Path $PSHOME 'powershell.exe'
    $checks = @(
        @{name='native-and-dart'; executable=$powershell; arguments=@('-NoProfile','-File','tool/check.ps1')},
        @{name='watchlist-ui'; executable=$dart; arguments=@('run','tool/verify_watchlist_ui.dart')},
        @{name='watchlist-stability'; executable=$dart; arguments=@('run','tool/verify_watchlist_stability.dart')},
        @{name='code-reload'; executable=$dart; arguments=@('run','tool/verify_watchlist_reload.dart')},
        @{name='development-launcher'; executable=$dart; arguments=@('run','tool/verify_dev_launcher.dart')},
        @{name='development-failures'; executable=$dart; arguments=@('run','tool/verify_dev_failures.dart')},
        @{name='aot-package'; executable=$powershell; arguments=@('-NoProfile','-File','tool/package.ps1','-Name',$Name)},
        @{name='aot-launch'; executable=$powershell; arguments=@('-NoProfile','-File','tool/verify_package.ps1','-Zip',"build/$Name-windows-x64.zip",'-ReportPath','reports/mvp/package.json')},
        @{name='package-failures'; executable=$powershell; arguments=@('-NoProfile','-File','tool/verify_package_failures.ps1','-Zip',"build/$Name-windows-x64.zip")}
    )
    try {
        foreach ($check in $checks) {
            Write-Output "Starting $($check.name)"
            $start = [Diagnostics.ProcessStartInfo]::new()
            $start.FileName = $check.executable
            # All arguments are fixed relative paths or the validated application name.
            $start.Arguments = $check.arguments -join ' '
            $start.WorkingDirectory = $projectRoot
            $start.UseShellExecute = $false
            $start.CreateNoWindow = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            $timer = [Diagnostics.Stopwatch]::StartNew()
            $process = [Diagnostics.Process]::Start($start)
            try {
                $output = $process.StandardOutput.ReadToEndAsync()
                $errors = $process.StandardError.ReadToEndAsync()
                $deadline = [DateTime]::UtcNow.AddMinutes(15)
                while (!$process.WaitForExit(1000)) {
                    if ([DateTime]::UtcNow -gt $deadline) { throw "$($check.name) timed out" }
                }
                $output.Result | Set-Content -LiteralPath (Join-Path $reportDirectory "$($check.name).stdout.log") -Encoding UTF8
                $errors.Result | Set-Content -LiteralPath (Join-Path $reportDirectory "$($check.name).stderr.log") -Encoding UTF8
                $report.checks += [ordered]@{name=$check.name; exit_code=$process.ExitCode; elapsed_ms=$timer.ElapsedMilliseconds}
                $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
                if ($process.ExitCode -ne 0) { throw "$($check.name) failed. See reports/mvp/$($check.name).stderr.log and stdout.log" }
                Write-Output "Passed $($check.name)"
            } finally {
                if (!$process.HasExited) {
                    & taskkill.exe /PID $process.Id /T /F | Out-Null
                    $process.WaitForExit()
                }
                $process.Dispose()
            }
        }
        $manifest = Get-Content -LiteralPath "build/$Name-windows-x64/manifest.json" -Raw | ConvertFrom-Json
        if ($manifest.build.source_dirty -or $manifest.build.git_commit -ne $report.source_commit) {
            throw 'Package source identity does not match the committed acceptance source.'
        }
        $report['package'] = [ordered]@{
            path="build/$Name-windows-x64.zip"
            bytes=(Get-Item -LiteralPath "build/$Name-windows-x64.zip").Length
            sha256=(Get-FileHash -LiteralPath "build/$Name-windows-x64.zip" -Algorithm SHA256).Hash.ToLowerInvariant()
            source_sha256=$manifest.build.source_sha256; native_abi=$manifest.native_abi
        }
        $report.local_acceptance_passed = $true
        Write-Output "PASS: local MVP acceptance. Clean Windows, human IME and mixed-monitor checks remain pending. Report: $reportPath"
    } catch {
        $report['error'] = $_.Exception.Message
        throw
    } finally {
        $report['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    }
} finally { Pop-Location }
