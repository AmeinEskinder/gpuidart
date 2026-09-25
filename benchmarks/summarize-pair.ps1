param(
    [Parameter(Mandatory)][string]$RunPrefix,
    [ValidateRange(1,100)][int]$Repetitions = 3,
    [ValidateSet('rust','dart','solid','shell')][string[]]$Implementations = @('rust','dart')
)
$ErrorActionPreference = 'Stop'
if (@($Implementations | Select-Object -Unique).Count -ne $Implementations.Count) { throw 'Implementations must be distinct' }
$root = Split-Path -Parent $PSScriptRoot
function AcrossRuns($Values) {
    $sorted = @($Values | Sort-Object)
    if (-not $sorted.Count) { return $null }
    $middle = [int][math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2) { $sorted[$middle] } else { ($sorted[$middle - 1] + $sorted[$middle]) / 2 }
    return @{ runs = $sorted.Count; median = $median; min = $sorted[0]; max = $sorted[-1] }
}
$observations = @(for ($repeat = 0; $repeat -lt $Repetitions; $repeat++) {
    $directories = Get-ChildItem -LiteralPath (Join-Path $root 'reports/comparison') -Directory |
        Where-Object { $_.Name -eq "$RunPrefix-$repeat" -or $_.Name -like "$RunPrefix-$repeat-retry*" } | Sort-Object Name
    foreach ($directory in $directories) {
        & "$PSScriptRoot/analyze.ps1" -Directory $directory.FullName
        $analysis = Get-Content -Raw (Join-Path $directory.FullName 'analysis.json') | ConvertFrom-Json
        foreach ($item in $analysis) {
            if ($item.implementation -notin $Implementations) { throw "Unexpected implementation in series: $($item.implementation)" }
            $item
        }
    }
})
$groups = @(foreach ($workload in @('idle','scroll','cell','burst')) {
    foreach ($implementation in $Implementations) {
        $runs = @($observations | Where-Object { $_.implementation -eq $implementation -and $_.workload -eq $workload })
        $completed = @($runs | Where-Object { $null -ne $_.duration_ms })
        @{
            implementation = $implementation; workload = $workload
            attempts = $runs.Count; completed = $completed.Count
            correctness_failures = @($completed | Where-Object { $null -ne $_.correctness -and -not $_.correctness.passed }).Count
            equal_work_timing_eligible = @($completed | Where-Object equal_work_timing_eligible).Count
            injected_inputs = @($completed.input_count)
            driver_deadline_misses = @($completed.scheduled_inputs_missed)
            driver_excess_inputs = @($completed.input_delivery.excess)
            cpu_percent_one_core = AcrossRuns $completed.cpu_percent_one_core
            working_set_mib = AcrossRuns @($completed | ForEach-Object { $_.working_set_bytes.p50 / 1MB })
            private_mib = AcrossRuns @($completed | ForEach-Object { $_.private_bytes.p50 / 1MB })
            window_available_ms = AcrossRuns $completed.window_available_ms
            native_draw_by_run = @($completed | Where-Object { $null -ne $_.native_diagnostics } | ForEach-Object { @{ run_id = $_.run_id; histogram = $_.native_diagnostics.draw; scope = $_.native_diagnostics.scope } })
            solid_draw_by_run = @($completed | Where-Object { $null -ne $_.solid_draw_overlay } | ForEach-Object { @{ run_id = $_.run_id; overlay = $_.solid_draw_overlay } })
            application_work_by_run = @($completed | ForEach-Object { @{ run_id = $_.run_id; work = $_.application_work } })
            publication_by_run = @($completed | Where-Object { $null -ne $_.dart_publication } | ForEach-Object { @{ run_id = $_.run_id; publication = $_.dart_publication } })
        }
    }
})
@{
    run_prefix = $RunPrefix; repetitions = $Repetitions; implementations = $Implementations
    summary_scope = 'All completed observations, including cadence differences and correctness failures. Memory summarizes per-run sample medians. Drawing/publication percentiles remain individual, unpooled histograms.'
    groups = $groups; observations = $observations
} | ConvertTo-Json -Depth 18 | Set-Content (Join-Path $root "reports/comparison/$RunPrefix-summary.json") -Encoding UTF8
Write-Output "Summarized $($observations.Count) observations for $RunPrefix."
