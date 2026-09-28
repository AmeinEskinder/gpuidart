param(
    [Parameter(Mandatory)][string]$RunPrefix,
    [string]$Title = "Comparison series $RunPrefix"
)
# Renders reports/comparison/<prefix>-summary.json (from summarize-pair.ps1)
# as Markdown tables: reliability, memory, CPU, window availability and the
# per-run application histograms. Numbers are copied, not recomputed, so the
# tables carry the summary's medians across runs and its min/max ranges.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$summaryPath = Join-Path $root "reports/comparison/$RunPrefix-summary.json"
$summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
$implementations = @($summary.implementations)
$workloads = @('idle','scroll','cell','burst')
$labels = @{ rust = 'Rust + GPUI Kit'; dart = 'Dart AOT'; solid = 'GPUIX/Solid/Bun'; shell = 'Shell/QuickJS'; flutter = 'Flutter Windows' }
function Label($implementation) { if ($labels.ContainsKey($implementation)) { $labels[$implementation] } else { $implementation } }
function GroupFor($implementation, $workload) { $summary.groups | Where-Object { $_.implementation -eq $implementation -and $_.workload -eq $workload } | Select-Object -First 1 }
function Range($value, [int]$digits = 2) {
    if ($null -eq $value -or $null -eq $value.median) { return 'n/a' }
    $format = "{0:F$digits}"
    return (($format -f $value.median) + ' [' + ($format -f $value.min) + ', ' + ($format -f $value.max) + ']')
}
$lines = [Collections.Generic.List[string]]::new()
$lines.Add("# $Title")
$lines.Add('')
$lines.Add("Rendered from [$RunPrefix-summary.json]($RunPrefix-summary.json): $($summary.repetitions) rotated repetitions of each workload in " + (($implementations | ForEach-Object { Label $_ }) -join ', ') + '. Each cell is the median across completed runs with the [min, max] range; memory is the per-run p50 of 250 ms process samples, and CPU is process time over the measured interval with one logical core as 100 percent.')
$lines.Add('')
$lines.Add('## Reliability')
$lines.Add('')
$lines.Add('| Workload | Implementation | Attempts | Completed | Correctness failures | Equal-work eligible | Driver deadline misses per run |')
$lines.Add('| --- | --- | ---: | ---: | ---: | ---: | --- |')
foreach ($workload in $workloads) {
    foreach ($implementation in $implementations) {
        $group = GroupFor $implementation $workload
        if (-not $group) { continue }
        $misses = @($group.driver_deadline_misses | ForEach-Object { "$_" }) -join ', '
        $lines.Add("| $workload | $(Label $implementation) | $($group.attempts) | $($group.completed) | $($group.correctness_failures) | $($group.equal_work_timing_eligible) | $misses |")
    }
}
$lines.Add('')
$lines.Add('## Memory, MiB')
$lines.Add('')
$lines.Add('| Workload | Implementation | Working set median [min, max] | Private bytes median [min, max] |')
$lines.Add('| --- | --- | ---: | ---: |')
foreach ($workload in $workloads) {
    foreach ($implementation in $implementations) {
        $group = GroupFor $implementation $workload
        if (-not $group) { continue }
        $lines.Add("| $workload | $(Label $implementation) | $(Range $group.working_set_mib) | $(Range $group.private_mib) |")
    }
}
$lines.Add('')
$lines.Add('## CPU, percent of one logical core')
$lines.Add('')
$lines.Add('| Workload | Implementation | CPU median [min, max] |')
$lines.Add('| --- | --- | ---: |')
foreach ($workload in $workloads) {
    foreach ($implementation in $implementations) {
        $group = GroupFor $implementation $workload
        if (-not $group) { continue }
        $lines.Add("| $workload | $(Label $implementation) | $(Range $group.cpu_percent_one_core 1) |")
    }
}
$lines.Add('')
$lines.Add('## Window availability, ms from process launch to a discovered HWND')
$lines.Add('')
$lines.Add('| Implementation | Median [min, max] over every workload run |')
$lines.Add('| --- | ---: |')
foreach ($implementation in $implementations) {
    $values = @($workloads | ForEach-Object { GroupFor $implementation $_ } | Where-Object { $_ } | ForEach-Object { $_.window_available_ms } | Where-Object { $null -ne $_.median })
    if (-not $values.Count) { continue }
    $medians = @($values | ForEach-Object { $_.median } | Sort-Object)
    $middle = [int][math]::Floor($medians.Count / 2)
    $median = if ($medians.Count % 2) { $medians[$middle] } else { ($medians[$middle - 1] + $medians[$middle]) / 2 }
    $min = ($values | ForEach-Object { $_.min } | Measure-Object -Minimum).Minimum
    $max = ($values | ForEach-Object { $_.max } | Measure-Object -Maximum).Maximum
    $lines.Add("| $(Label $implementation) | $('{0:F0}' -f $median) [$('{0:F0}' -f $min), $('{0:F0}' -f $max)] |")
}
$lines.Add('')
$lines.Add('## Application frame histograms, per run')
$lines.Add('')
$lines.Add('Each row is one run''s own cumulative histogram since window creation, including startup and warmup; percentiles are not pooled across runs and the estimators differ between fixtures.')
$lines.Add('')
$lines.Add('| Workload | Implementation | Run | Samples | p50 µs | p95 µs | p99 µs | Max µs | Source |')
$lines.Add('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |')
foreach ($workload in $workloads) {
    foreach ($implementation in $implementations) {
        $group = GroupFor $implementation $workload
        if (-not $group) { continue }
        foreach ($entry in @($group.native_draw_by_run)) {
            $h = $entry.histogram
            if ($null -eq $h) { continue }
            $lines.Add("| $workload | $(Label $implementation) | $($entry.run_id) | $($h.samples) | $($h.p50_us) | $($h.p95_us) | $($h.p99_us) | $($h.max_us) | native draw |")
        }
        foreach ($entry in @($group.flutter_frames_by_run)) {
            foreach ($phase in @('build_us','raster_us','total_us')) {
                $h = $entry.frames.$phase
                if ($null -eq $h -or -not $h.samples) { continue }
                $lines.Add("| $workload | $(Label $implementation) | $($entry.run_id) | $($h.samples) | $($h.p50) | $($h.p95) | $($h.p99) | $($h.max) | FrameTiming $($phase -replace '_us$','') |")
            }
        }
    }
}
$lines.Add('')
$lines.Add('## Application work, per run')
$lines.Add('')
$lines.Add('| Workload | Implementation | Run | Updates | Cells written | Rows or cells built |')
$lines.Add('| --- | --- | --- | ---: | ---: | ---: |')
foreach ($workload in $workloads) {
    foreach ($implementation in $implementations) {
        $group = GroupFor $implementation $workload
        if (-not $group) { continue }
        foreach ($entry in @($group.application_work_by_run)) {
            $work = $entry.work
            if ($null -eq $work) { continue }
            $built = if ($null -ne $work.flutter_row_builds) { $work.flutter_row_builds } elseif ($null -ne $work.shell_cell_builds) { $work.shell_cell_builds } elseif ($null -ne $work.solid_row_components_created) { $work.solid_row_components_created } else { '' }
            $lines.Add("| $workload | $(Label $implementation) | $($entry.run_id) | $($work.updates) | $($work.cells_written) | $built |")
        }
    }
}
$lines.Add('')
$output = Join-Path $root "reports/comparison/$RunPrefix.md"
($lines -join "`n") + "`n" | Set-Content -LiteralPath $output -Encoding UTF8 -NoNewline
Write-Output "Wrote $output"
