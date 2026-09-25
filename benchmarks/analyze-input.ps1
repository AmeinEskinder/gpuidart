param([Parameter(Mandatory)][string]$Directory)
$ErrorActionPreference = 'Stop'
$runPath = Join-Path $Directory 'run.json'
if (-not (Test-Path $runPath)) { $runPath = Join-Path $Directory 'failure.json' }
$run = Get-Content -Raw $runPath | ConvertFrom-Json
$native = Get-Content -Raw (Join-Path $Directory 'native-input-trace.json') | ConvertFrom-Json
$applicationPath = Join-Path $Directory 'application.json.input-trace.json'
$application = if ($run.implementation -eq 'dart' -and (Test-Path $applicationPath)) {
    Get-Content -Raw $applicationPath | ConvertFrom-Json
} elseif ($run.implementation -eq 'rust') { $native } else { @() }

function IndexEvents($Events) {
    $index = @{}
    foreach ($event in $Events) {
        if ($null -eq $event.sequence) { continue }
        $key = "$($event.sequence)/$($event.stage)"
        if (-not $index.ContainsKey($key)) { $index[$key] = @() }
        $index[$key] += $event
    }
    return $index
}
$nativeIndex = IndexEvents $native
$applicationIndex = IndexEvents $application
$appliedRevisions = @{}
foreach ($event in $native | Where-Object { $_.stage -eq 'update_applied' -and $null -ne $_.data.revision }) {
    $appliedRevisions[[string]$event.data.revision] = $event
}
$observations = @(foreach ($input in $run.inputs) {
    $sequence = $input.sequence
    $down = @($nativeIndex["$sequence/gpui_mouse_down"] | Where-Object { $null -ne $_ })
    $up = @($nativeIndex["$sequence/gpui_mouse_up"] | Where-Object { $null -ne $_ })
    $click = @($nativeIndex["$sequence/native_click_handler"] | Where-Object { $null -ne $_ })
    $handler = @($applicationIndex["$sequence/application_handler"] | Where-Object { $null -ne $_ })
    $observed = @($applicationIndex["$sequence/state_observed"] | Where-Object { $null -ne $_ })
    $ack = @($applicationIndex["$sequence/applied_acknowledged"] | Where-Object { $null -ne $_ })
    $applied = if ($run.implementation -eq 'rust') {
        @($nativeIndex["$sequence/update_applied"] | Where-Object { $null -ne $_ })
    } elseif ($handler.Count -eq 1) {
        @($appliedRevisions[[string]$handler[0].data.target_revision] | Where-Object { $null -ne $_ })
    } else { @() }
    $applied = @($applied | Where-Object { $null -ne $_ })
    $expected = if ($handler.Count -eq 1) { 'Tick {0:D6}' -f [int]$handler[0].data.update_ordinal } else { $null }
    $stateMatches = $observed.Count -eq 1 -and $observed[0].data.value -eq $expected
    if ($run.implementation -eq 'dart') { $stateMatches = $stateMatches -and $observed[0].data.native.value -eq $expected }
    $gap = if ($input.packets_accepted -ne 2) { 'injection acceptance unverified' }
        elseif ($down.Count -ne 1) { 'injection to GPUI mouse down' }
        elseif ($up.Count -ne 1) { 'mouse down to GPUI mouse up' }
        elseif ($click.Count -ne 1) { 'GPUI mouse events to native click handler' }
        elseif ($handler.Count -ne 1) { 'native click handler to application handler' }
        elseif ($applied.Count -ne 1) { 'application handler to native application of update' }
        elseif ($run.implementation -eq 'dart' -and $ack.Count -ne 1) { 'native application of update to Dart acknowledgement' }
        elseif (-not $stateMatches) { 'applied update to expected state readback' }
        else { $null }
    @{
        sequence = $sequence; packets_accepted = $input.packets_accepted
        mouse_down = $down.Count; mouse_up = $up.Count
        native_click_handler = $click.Count; application_handler = $handler.Count
        native_update_applied = $applied.Count; dart_acknowledged = $ack.Count
        state_observed = $observed.Count; state_matches = $stateMatches; first_gap = $gap
        mouse_down_positions = @($down.data); mouse_up_positions = @($up.data)
    }
})
$result = @{
    implementation = $run.implementation; workload = $run.workload; run_id = $run.run_id
    inputs = $observations.Count; complete_chains = @($observations | Where-Object { $null -eq $_.first_gap }).Count
    gaps = @($observations | Where-Object { $null -ne $_.first_gap })
    observations = $observations
    limit = 'Diagnostic builds and per-update readbacks; ineligible for performance comparison. A missing GPUI event does not by itself establish driver fault. QPC and Dart elapsed times are not presentation timestamps.'
}
$result | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Directory 'input-analysis.json') -Encoding UTF8
Write-Output "$($run.implementation) $($run.workload): $($result.complete_chains)/$($result.inputs) complete traced chains; $($result.gaps.Count) gaps."
