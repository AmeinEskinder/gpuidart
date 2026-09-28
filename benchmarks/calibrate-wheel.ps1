param(
    [ValidateSet('rust','dart','solid','shell','flutter')][string]$Implementation = 'flutter',
    [int[]]$Deltas = @(-120),
    [int]$Events = 1,
    [int]$IntervalMs = 50
)
# Measures how far one fixture scrolls per injected wheel event: starts the
# fixture, activates it like run.ps1, sends $Events wheel events of each delta
# with the pointer over the table, then reads the fixture's own report. The
# fixture keeps running between deltas, so the offsets are cumulative and the
# script prints the difference for each delta.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Add-Type -Path (Join-Path $PSScriptRoot 'windows.cs') -ReferencedAssemblies System.Drawing
$folder = Join-Path $root "reports/comparison/calibration-$Implementation"
New-Item -ItemType Directory -Force $folder | Out-Null
$exe = switch ($Implementation) {
    rust { Join-Path $root 'target/release/gpui-native-comparison.exe' }
    dart { Join-Path $root 'build/gpui-dart-comparison.exe' }
    solid { Join-Path $root 'benchmarks/solid/dist/gpui-solid-comparison.exe' }
    shell { throw 'Shell reports a visible range rather than a displacement; calibrate it from a scroll run' }
    flutter { Join-Path $root 'benchmarks/flutter/build/windows/x64/runner/Release/gpui_flutter_comparison.exe' }
}
$env:GPUIDART_LIBRARY = Join-Path $root 'target/release/gpuidart.dll'
$results = [Collections.Generic.List[object]]::new()
[BenchmarkWindow]::Initialize()
try {
    foreach ($delta in $Deltas) {
        $output = Join-Path $folder "delta-$delta.json"
        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
        $app = [BenchmarkWindow]::Start($exe, ('"' + $output + '"'), $folder, $false)
        $window = [IntPtr]::Zero
        $started = [Diagnostics.Stopwatch]::StartNew()
        while ($window -eq [IntPtr]::Zero -and $started.Elapsed.TotalSeconds -lt 45) {
            $app.Refresh()
            if ($app.HasExited) { throw "Application exited with $($app.ExitCode)" }
            $window = [BenchmarkWindow]::Find($app.Id)
            Start-Sleep -Milliseconds 10
        }
        if ($window -eq [IntPtr]::Zero) { throw 'No application window' }
        [BenchmarkWindow]::Prepare($window, $true)
        Start-Sleep -Seconds 2
        [BenchmarkWindow]::Prepare($window, $true)
        Start-Sleep -Milliseconds 250
        [BenchmarkWindow]::RequireFocus($window)
        [BenchmarkWindow]::Pointer($window, 400, 270)
        Start-Sleep -Milliseconds 200
        for ($i = 0; $i -lt $Events; $i++) { [BenchmarkWindow]::Wheel($window, $delta); Start-Sleep -Milliseconds $IntervalMs }
        Start-Sleep -Milliseconds 700
        $null = [BenchmarkWindow]::Click($window, 157)
        if (-not $app.WaitForExit(15000)) { throw 'Application did not save its report' }
        $report = Get-Content -Raw -LiteralPath $output | ConvertFrom-Json
        $scroll = switch ($Implementation) { rust { $report.scroll_y }; dart { $report.native.tables.table.scroll_y }; solid { $report.scroll_offset[1] }; flutter { $report.scroll_y } }
        $results.Add([ordered]@{ implementation = $Implementation; delta = $delta; events = $Events; interval_ms = $IntervalMs; scroll_y = $scroll; per_event = $scroll / $Events })
        Write-Output "$Implementation delta $delta x $Events -> scroll_y $scroll ($($scroll / $Events) per event)"
    }
} finally {
    [BenchmarkWindow]::Finish()
}
$results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'calibration.json') -Encoding UTF8
