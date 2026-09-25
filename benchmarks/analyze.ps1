param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference = 'Stop'
function Distribution($Values) {
    $sorted = @($Values | Sort-Object)
    if (-not $sorted.Count) { return $null }
    return @{ samples = $sorted.Count; p50 = $sorted[[math]::Ceiling(0.50 * $sorted.Count) - 1]; p95 = $sorted[[math]::Ceiling(0.95 * $sorted.Count) - 1]; p99 = $sorted[[math]::Ceiling(0.99 * $sorted.Count) - 1]; max = $sorted[-1] }
}
function ColumnNumbers($Rows, [string]$Name) {
    foreach ($row in $Rows) {
        $value = 0.0
        if ([double]::TryParse($row.$Name, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -ge 0) { $value }
    }
}
$results = @(foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter run.json -Recurse) {
    $run = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    if ($run.purpose -ne 'foreground measurement') {
        @{ implementation = $run.implementation; workload = $run.workload; run_id = $run.run_id; status = "excluded from performance: $($run.purpose)"; correctness = $run.correctness; equal_work_timing_eligible = $false; input_count = $run.input_count; scheduled_inputs_missed = $run.input_deadlines_missed }
        continue
    }
    $applicationPath = Join-Path $file.DirectoryName 'application.json'
    $application = if (Test-Path -LiteralPath $applicationPath) { Get-Content -Raw -LiteralPath $applicationPath | ConvertFrom-Json } else { $null }
    $native = switch ($run.implementation) { rust { $application }; dart { $application.native }; default { $null } }
    $rate = switch ($run.workload) { idle { 0 }; scroll { 60 }; cell { 5 }; burst { 30 } }
    $plannedInputs = if ($null -ne $run.seconds_requested) { $run.seconds_requested * $rate } else { $null }
    $excessInputs = if ($null -ne $plannedInputs) { [math]::Max(0, $run.input_count - $plannedInputs) } else { $null }
    $uninjectedInputs = if ($null -ne $plannedInputs) { [math]::Max(0, $plannedInputs - $run.input_count) } else { $null }
    $frames = @()
    $tracePath = Join-Path $file.DirectoryName 'present.csv'
    if (Test-Path -LiteralPath $tracePath) {
        $traceRows = @(Import-Csv -LiteralPath $tracePath)
        if ($traceRows.Count -gt 0) {
            foreach ($required in @('CPUStartQPC','ProcessID','DisplayedTime','MsBetweenPresents','MsBetweenDisplayChange')) {
                if ($required -notin $traceRows[0].PSObject.Properties.Name) { throw "PresentMon CSV is missing $required" }
            }
            $frames = @($traceRows | Where-Object { [int]$_.ProcessID -eq $run.process_id -and [double]$_.CPUStartQPC -ge $run.start_qpc -and [double]$_.CPUStartQPC -lt $run.end_qpc })
            $swapchains = @($frames.SwapChainAddress | Sort-Object -Unique)
            if ($swapchains.Count -gt 1) { throw 'Multiple swapchains require explicit selection before aggregation' }
        }
    }
    $displayed = @($frames | Where-Object { $_.DisplayedTime -ne 'NA' })
    $targetMs = switch ($run.workload) { scroll { 1000.0 / 60 } burst { 1000.0 / 30 } cell { 200.0 } idle { $null } }
    # The first interval starts before the measurement window.
    $intervals = @(ColumnNumbers @($displayed | Select-Object -Skip 1) 'MsBetweenDisplayChange')
    $missedSlots = $null
    if ($targetMs -and $intervals.Count) {
        $missedSlots = ($intervals | ForEach-Object { [math]::Max(0, [math]::Round($_ / $targetMs) - 1) } | Measure-Object -Sum).Sum
    }
    @{
        implementation = $run.implementation; workload = $run.workload; run_id = $run.run_id
        correctness = $run.correctness
        equal_work_timing_eligible = ($null -ne $plannedInputs -and $excessInputs -eq 0 -and $uninjectedInputs -eq 0 -and $run.input_deadlines_missed -eq 0 -and ($null -eq $run.correctness -or $run.correctness.passed))
        input_delivery = @{ planned = $plannedInputs; injected = $run.input_count; excess = $excessInputs; uninjected = $uninjectedInputs }
        status = $(if ($frames.Count) { 'ETW captured; response-frame correlation and parity review still required' } else { 'presentation unavailable' })
        scheduled_inputs_missed = $run.input_deadlines_missed
        input_count = $run.input_count; duration_ms = $run.duration_ms
        delivery_quality = $(if ($run.input_deadlines_missed -gt 0) { 'driver missed deadlines; exclude from matched-cadence ranking' } else { 'no skipped input deadlines; inspect recorded input jitter separately' })
        cpu_percent_one_core = $run.cpu_percent_one_core
        working_set_bytes = Distribution @($run.process_samples.working_set_bytes)
        private_bytes = Distribution @($run.process_samples.private_bytes)
        window_available_ms = $run.window_available_ms
        application_work = $(if ($application) { @{
            updates = $application.updates; cells_written = $application.cells_written
            shell_view_builds = $application.view_builds; shell_cell_builds = $application.cell_builds
            shell_visible_range = $application.visible_range
            solid_row_components_created = $application.row_components_created
            solid_mounted_window = $application.mounted_window; solid_scroll_offset = $application.scroll_offset
        } } else { $null })
        native_diagnostics = $(if ($native) { @{
            scope = $application.scope
            draw = $native.draw
            dirty_to_present_submit = $native.dirty_to_present_submit
            input_to_frame = $native.input_to_frame
            limit = 'Cumulative native histories include startup and warmup; no changed-cell presentation correlation'
        } } else { $null })
        solid_draw_overlay = $(if ($run.implementation -eq 'solid') { @{
            scope = $application.scope; statistics = $application.draw_overlay
        } } else { $null })
        dart_publication = $(if ($run.implementation -eq 'dart') { @{
            scope = 'Dataset edits from delivered workload clicks, through the applied acknowledgement; initial upload reported separately'
            statistics = $application.publication
            limit = 'Application-defined percentile estimator; do not add stage percentiles or treat acknowledgement as presentation'
        } } else { $null })
        presentation = $(if ($frames.Count) { @{
            frames = $frames.Count; frames_not_displayed = $frames.Count - $displayed.Count
            between_presents_ms = Distribution @(ColumnNumbers @($frames | Select-Object -Skip 1) 'MsBetweenPresents')
            between_display_changes_ms = Distribution $intervals
            estimated_missed_workload_slots = $missedSlots; target_period_ms = $targetMs
            input_associated_display_ms = Distribution @(ColumnNumbers $displayed 'MsAllInputToPhotonLatency')
            input_to_response_present_ms = $null
            latency_limit = 'ETW input association does not prove the frame contains the changed cell'
        } } else { $null })
    }
})
foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter failure.json -Recurse) {
    if (Test-Path -LiteralPath (Join-Path $file.DirectoryName 'run.json')) { continue }
    $failure = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    $results += @{
        implementation = $failure.implementation; workload = $failure.workload; run_id = $failure.run_id
        status = 'incomplete or legacy failed observation; retained for reliability accounting'
        failure = $failure; equal_work_timing_eligible = $false; presentation = $null
    }
}
$results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Directory 'analysis.json') -Encoding UTF8
