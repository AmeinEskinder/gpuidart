param(
    [ValidateSet('rust','dart','solid','shell')][string]$Implementation = 'dart',
    [ValidateSet('idle','scroll','cell','burst')][string]$Workload = 'idle',
    [ValidateRange(2,120)][int]$Seconds = 10,
    [string]$RunId = 'pilot',
    [switch]$CapturePresent,
    [switch]$BackgroundSmoke,
    [switch]$Packaged,
    [switch]$TraceInput,
    [switch]$NoPointerWarmup
)
$ErrorActionPreference = 'Stop'
if ($BackgroundSmoke -and $CapturePresent) { throw 'BackgroundSmoke cannot capture presentation measurements' }
if ($TraceInput -and ($BackgroundSmoke -or $Packaged -or $Implementation -notin @('rust','dart'))) { throw 'Input tracing requires an unpackaged foreground Rust or Dart fixture' }
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Add-Type -Path (Join-Path $PSScriptRoot 'windows.cs') -ReferencedAssemblies System.Drawing
$folder = Join-Path $root "reports/comparison/$RunId/$Implementation-$Workload"
New-Item -ItemType Directory -Force $folder | Out-Null
$appOutput = Join-Path $folder 'application.json'
foreach ($name in @('application.json','run.json','failure.json')) {
    if (Test-Path -LiteralPath (Join-Path $folder $name)) { throw "Attempt output already exists in $folder. Choose another RunId." }
}
$exe = switch ($Implementation) {
    rust { Join-Path $root 'target/release/gpui-native-comparison.exe' }
    dart { Join-Path $root 'build/gpui-dart-comparison.exe' }
    solid { Join-Path $root 'benchmarks/solid/dist/gpui-solid-comparison.exe' }
    shell { Join-Path $root 'target/release/gpui-component-shell.exe' }
}
$arguments = if ($Implementation -eq 'shell') { '"' + (Join-Path $root 'benchmarks/shell') + '"' } else { '"' + $appOutput + '"' }
$env:GPUIDART_LIBRARY = Join-Path $root 'target/release/gpuidart.dll'
$env:GPUIDART_INPUT_TRACE = $null
$env:GPUIDART_NATIVE_TRACE = $null
if ($TraceInput) {
    $env:GPUIDART_INPUT_TRACE = '1'
    $env:GPUIDART_NATIVE_TRACE = Join-Path $folder 'native-input-trace.json'
    $env:GPUIDART_LIBRARY = Join-Path $root 'build/comparison-trace/gpuidart.dll'
    if ($Implementation -eq 'rust') { $exe = Join-Path $root 'build/comparison-trace/gpui-native-comparison.exe' }
}
if ($Packaged) {
    $packageFolder = Join-Path $root "build/comparison/$Implementation"
    $exe = Join-Path $packageFolder (Split-Path -Leaf $exe)
    if ($Implementation -eq 'shell') { $arguments = '"' + $packageFolder + '"' }
    $env:GPUIDART_LIBRARY = Join-Path $packageFolder 'gpuidart.dll'
}
$trace = $null
$traceStatus = 'not requested'
$app = $null
$window = [IntPtr]::Zero
$observationExitCode = 0
[BenchmarkWindow]::Initialize()
try {
    if ($CapturePresent) {
        $trace = Start-Process -FilePath (Join-Path $root '.tools/presentmon/PresentMon.exe') -ArgumentList @(
            '--process_name', [IO.Path]::GetFileName($exe), '--output_file', ('"' + (Join-Path $folder 'present.csv') + '"'),
            '--qpc_time', '--timed', ($Seconds + 60), '--terminate_after_timed', '--terminate_on_proc_exit', '--no_console_stats', '--session_name', ('gpuidart-' + $PID)
        ) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $folder 'present.stdout.log') -RedirectStandardError (Join-Path $folder 'present.stderr.log')
        Start-Sleep -Milliseconds 700
        $trace.Refresh()
        $traceStatus = if ($trace.HasExited) { 'failed; see present.stderr.log' } else { 'running; validate CSV after exit' }
    }
    $startup = [Diagnostics.Stopwatch]::StartNew()
    $launchQpc = [Diagnostics.Stopwatch]::GetTimestamp()
    $app = [BenchmarkWindow]::Start($exe, $arguments, $folder, $Packaged)
    while ($window -eq [IntPtr]::Zero -and $startup.Elapsed.TotalSeconds -lt 45) {
        $app.Refresh()
        if ($app.HasExited) { throw "Application exited with $($app.ExitCode); see $folder/stderr.log" }
        $window = [BenchmarkWindow]::Find($app.Id)
        Start-Sleep -Milliseconds 10
    }
    if ($window -eq [IntPtr]::Zero) { throw 'No visible application window within 45 seconds' }
    $windowAvailableMs = $startup.Elapsed.TotalMilliseconds
    [BenchmarkWindow]::Prepare($window, -not $BackgroundSmoke)
    Start-Sleep -Seconds 3
    [BenchmarkWindow]::Prepare($window, -not $BackgroundSmoke)
    Start-Sleep -Milliseconds 250
    if (-not $BackgroundSmoke) {
        [BenchmarkWindow]::RequireFocus($window)
        [BenchmarkWindow]::Capture($window, (Join-Path $folder 'before.png'))
    }
    $dpiScale = [BenchmarkWindow]::Scale($window)
    $windowDpi = [BenchmarkWindow]::GetDpiForWindow($window)
    $clientPixels = [BenchmarkWindow]::Client($window)
    if (-not $BackgroundSmoke -and -not $NoPointerWarmup) {
        switch ($Workload) {
            scroll { [BenchmarkWindow]::Pointer($window, 400, 270) }
            cell { [BenchmarkWindow]::Pointer($window, 140, 69) }
            burst { [BenchmarkWindow]::Pointer($window, 140, 113) }
        }
        Start-Sleep -Milliseconds 100
    }
    $app.Refresh()
    $cpuStart = $app.TotalProcessorTime.TotalMilliseconds
    $samples = [Collections.Generic.List[object]]::new()
    $inputTimes = [Collections.Generic.List[object]]::new()
    $frequency = [Diagnostics.Stopwatch]::Frequency
    $startQpc = [Diagnostics.Stopwatch]::GetTimestamp()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $period = switch ($Workload) { idle { [double]::PositiveInfinity } scroll { 1000.0 / 60 } cell { 200.0 } burst { 1000.0 / 30 } }
    $plannedInputs = $Seconds * $(switch ($Workload) { idle { 0 } scroll { 60 } cell { 5 } burst { 30 } })
    $wheelDelta = if ($Implementation -eq 'solid') { -156 } else { -120 }
    $nextInput = 0.0
    $nextSlot = 0
    $nextSample = 0.0
    $missedInputDeadlines = 0
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        if (-not $BackgroundSmoke) { [BenchmarkWindow]::RequireFocus($window) }
        $elapsed = $timer.Elapsed.TotalMilliseconds
        if ($elapsed -ge $Seconds * 1000) { break }
        if ($nextSlot -lt $plannedInputs -and $elapsed -ge $nextInput) {
            $late = $elapsed - $nextInput
            if ($late -ge $period) {
                $skipped = [math]::Floor($late / $period)
                $missedInputDeadlines += $skipped
                $nextSlot += $skipped
                $nextInput = $nextSlot * $period
            }
            $qpc = [Diagnostics.Stopwatch]::GetTimestamp()
            $sequence = $inputTimes.Count + 1
            $sentPackets = $null
            switch ($Workload) {
                scroll { if ($BackgroundSmoke) { [BenchmarkWindow]::MessageWheel($window, $wheelDelta) } else { [BenchmarkWindow]::Wheel($window, $wheelDelta) } }
                cell { if ($BackgroundSmoke) { [BenchmarkWindow]::MessageClick($window, 69) } else { $sentPackets = [BenchmarkWindow]::Click($window, 69, $sequence) } }
                burst { if ($BackgroundSmoke) { [BenchmarkWindow]::MessageClick($window, 113) } else { $sentPackets = [BenchmarkWindow]::Click($window, 113, $sequence) } }
            }
            $inputTimes.Add(@{ sequence = $sequence; qpc = $qpc; injection_completed_qpc = [Diagnostics.Stopwatch]::GetTimestamp(); packets_accepted = $sentPackets; scheduled_ms = $nextInput; sent_ms = $elapsed })
            $nextSlot++
            $nextInput = $nextSlot * $period
        }
        if ($elapsed -ge $nextSample) {
            $app.Refresh()
            if ($app.HasExited) { throw 'Application exited during workload' }
            $samples.Add(@{ elapsed_ms = $elapsed; working_set_bytes = $app.WorkingSet64; private_bytes = $app.PrivateMemorySize64; cpu_ms = $app.TotalProcessorTime.TotalMilliseconds - $cpuStart })
            $nextSample += 250
        }
        [BenchmarkWindow]::Pause()
    }
    $endQpc = [Diagnostics.Stopwatch]::GetTimestamp()
    $app.Refresh()
    $durationMs = $timer.Elapsed.TotalMilliseconds
    $cpuMs = $app.TotalProcessorTime.TotalMilliseconds - $cpuStart
    Start-Sleep -Milliseconds 700
    if ($BackgroundSmoke) {
        [BenchmarkWindow]::CaptureOffscreen($window, (Join-Path $folder 'offscreen.png'))
        [BenchmarkWindow]::MessageClick($window, 157)
    } else {
        [BenchmarkWindow]::Capture($window, (Join-Path $folder 'after.png'))
        $null = [BenchmarkWindow]::Click($window, 157)
    }
    if ($Implementation -eq 'shell') {
        Start-Sleep -Seconds 2
        [BenchmarkWindow]::Close($window)
    }
    if (-not $app.WaitForExit(15000)) { throw 'Application did not save measurements and exit' }
    if ($Implementation -eq 'shell') {
        $line = Get-Content (Join-Path $folder 'stdout.log'),(Join-Path $folder 'stderr.log') | Where-Object { $_ -match 'BENCHMARK_RESULT (\{.*\})' } | Select-Object -Last 1
        if ($line -match 'BENCHMARK_RESULT (\{.*\})') { $Matches[1] | Set-Content -LiteralPath $appOutput -Encoding UTF8 }
    }
    if (-not (Test-Path -LiteralPath $appOutput)) { throw 'Application produced no verification report' }
    $verification = Get-Content -Raw -LiteralPath $appOutput | ConvertFrom-Json
    $verificationIssues = [Collections.Generic.List[string]]::new()
    $expectedUpdates = if ($Workload -in @('cell','burst')) { $inputTimes.Count } else { 0 }
    if ($verification.updates -ne $expectedUpdates) { $verificationIssues.Add("$($verification.updates) updates for $expectedUpdates injected clicks") }
    $expectedCells = $expectedUpdates * $(if ($Workload -eq 'burst') { 8 } else { 1 })
    if ($verification.cells_written -ne $expectedCells) { $verificationIssues.Add('Changed-cell count does not match injected input') }
    $expectedPrice = if ($expectedUpdates) { 'Tick {0:D6}' -f $expectedUpdates } else { '100.00' }
    if ($verification.first_price -ne $expectedPrice) { $verificationIssues.Add('Application final cell does not match injected input') }
    if ($Implementation -eq 'dart' -and $verification.native_first_price.value -ne $expectedPrice) { $verificationIssues.Add('Native final cell does not match injected input') }
    $visibleStart = switch ($Implementation) {
        rust { $verification.visible_rows.start }
        dart { $verification.native.tables.table.visible_rows.start }
        shell { $verification.visible_range[0] }
        solid { $verification.mounted_window.start }
    }
    if ($Workload -eq 'scroll' -and $visibleStart -le 0) { $verificationIssues.Add('Scroll input did not advance the visible row window') }
    $scrollY = switch ($Implementation) { rust { $verification.scroll_y }; dart { $verification.native.tables.table.scroll_y }; solid { $verification.scroll_offset[1] }; default { $null } }
    $expectedScrollY = if ($Workload -eq 'scroll') { -78 * $inputTimes.Count } else { 0 }
    if ($Implementation -in @('rust','dart','solid') -and ($null -eq $scrollY -or [math]::Abs($scrollY - $expectedScrollY) -gt 0.01)) { $verificationIssues.Add('Native scroll displacement does not match injected wheel input') }
    if ($Implementation -eq 'shell' -and $verification.cell_builds -le 0) { $verificationIssues.Add('Shell did not materialize any table cells') }
    if ($CapturePresent -and -not $trace.HasExited) { $trace.WaitForExit(15000) | Out-Null }
    $report = @{
        implementation = $Implementation; workload = $Workload; run_id = $RunId
        process_id = $app.Id; launch_qpc = $launchQpc
        packaged = [bool]$Packaged; isolated_path = [bool]$Packaged
        purpose = $(if ($TraceInput) { 'foreground input tracing; ineligible for performance comparison' } elseif ($BackgroundSmoke) { 'background fixture correctness; ineligible for performance comparison' } else { 'foreground measurement' })
        input_trace = [bool]$TraceInput; pointer_warmup = -not [bool]$NoPointerWarmup
        activation_clicks = [BenchmarkWindow]::ActivationClicks
        rows = 100000; seconds_requested = $Seconds; duration_ms = $durationMs
        harness_timer_resolution_ms = 1
        driver_wait = 'one-millisecond high resolution waitable timer'
        input_count = $inputTimes.Count; input_deadlines_missed = $missedInputDeadlines
        planned_inputs = $plannedInputs
        correctness = @{
            passed = $verificationIssues.Count -eq 0; issues = @($verificationIssues.ToArray())
            expected_updates = $expectedUpdates; observed_updates = $verification.updates
            expected_cells = $expectedCells; observed_cells = $verification.cells_written
            expected_price = $expectedPrice; application_price = $verification.first_price
            native_price = $(if ($Implementation -eq 'dart') { $verification.native_first_price.value } elseif ($Implementation -eq 'rust') { $verification.first_price } else { $null })
            expected_scroll_y = $expectedScrollY; observed_scroll_y = $scrollY
        }
        wheel_delta = $wheelDelta
        cpu_ms = $cpuMs; cpu_percent_one_core = 100 * $cpuMs / $durationMs
        logical_processors = [Environment]::ProcessorCount
        window_available_ms = $windowAvailableMs; startup_boundary = 'process launch to created HWND; window explicitly shown afterward; not first displayed frame'
        start_qpc = $startQpc; end_qpc = $endQpc; qpc_frequency = $frequency
        trace_status = $traceStatus; trace_exit_code = $(if ($trace -and $trace.HasExited) { $trace.ExitCode } else { $null }); dpi_scale = $dpiScale; window_dpi = $windowDpi
        client_pixels = $clientPixels
        inputs = $inputTimes; process_samples = $samples; exe_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
        native_library_sha256 = $(if ($Implementation -eq 'dart') { (Get-FileHash -Algorithm SHA256 -LiteralPath $env:GPUIDART_LIBRARY).Hash } else { $null })
        driver_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $PSScriptRoot 'windows.cs')).Hash
        runner_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $folder 'run.json') -Encoding UTF8
    if ($verificationIssues.Count) {
        $observationExitCode = 2
        Write-Warning "Correctness failure retained for $Implementation ${Workload}: $($verificationIssues -join '; '). $folder"
    } else {
        Write-Output "Verified $Implementation ${Workload}: $($inputTimes.Count) inputs; $expectedCells changed cells. $folder"
    }
} catch {
    @{
        implementation = $Implementation; workload = $Workload; run_id = $RunId
        status = 'interrupted observation; retain for reliability accounting'; error = $_.Exception.Message
        failed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        inputs = $inputTimes; scheduled_inputs_missed = $missedInputDeadlines
        process_samples = $samples
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'failure.json') -Encoding UTF8
    throw
} finally {
    [BenchmarkWindow]::Finish()
    if ($app -and -not $app.HasExited) {
        if ($window -ne [IntPtr]::Zero) { [BenchmarkWindow]::Close($window) }
        if (-not $app.WaitForExit(3000)) { Stop-Process -Id $app.Id }
    }
    if ($trace -and -not $trace.HasExited) { Stop-Process -Id $trace.Id }
}
if ($observationExitCode) { exit $observationExitCode }
