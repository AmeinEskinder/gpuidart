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
$results = foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter run.json -Recurse) {
    $run = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
    if ($run.purpose -ne 'foreground measurement') {
        @{ implementation = $run.implementation; workload = $run.workload; status = 'excluded: background correctness run' }
        continue
    }
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
        implementation = $run.implementation; workload = $run.workload
        status = $(if ($frames.Count) { 'ETW captured; response-frame correlation and parity review still required' } else { 'presentation unavailable' })
        scheduled_inputs_missed = $run.input_deadlines_missed
        cpu_percent_one_core = $run.cpu_percent_one_core
        working_set_bytes = Distribution @($run.process_samples.working_set_bytes)
        private_bytes = Distribution @($run.process_samples.private_bytes)
        window_available_ms = $run.window_available_ms
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
}
$results | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $Directory 'analysis.json') -Encoding UTF8
