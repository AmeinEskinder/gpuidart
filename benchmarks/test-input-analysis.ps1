$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $root ('.cache/input-analysis-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $folder | Out-Null
$inputs = @(1..4 | ForEach-Object { @{ sequence = $_; packets_accepted = 2 } })
@{ implementation = 'rust'; workload = 'cell'; run_id = 'synthetic'; inputs = $inputs } |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $folder 'run.json') -Encoding UTF8
$events = @(foreach ($sequence in 1..4) {
    foreach ($stage in @('gpui_mouse_down','gpui_mouse_up')) { @{ sequence = $sequence; stage = $stage; data = @{} } }
    if ($sequence -eq 2) { continue }
    @{ sequence = $sequence; stage = 'native_click_handler'; data = @{} }
    @{ sequence = $sequence; stage = 'application_handler'; data = @{ update_ordinal = $sequence } }
    if ($sequence -eq 3) { continue }
    @{ sequence = $sequence; stage = 'update_applied'; data = @{ updates = $sequence } }
    @{ sequence = $sequence; stage = 'state_observed'; data = @{ value = $(if ($sequence -eq 4) { 'wrong value' } else { 'Tick 000001' }) } }
})
$events | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $folder 'native-input-trace.json') -Encoding UTF8
& "$PSScriptRoot/analyze-input.ps1" -Directory $folder
$result = Get-Content -Raw (Join-Path $folder 'input-analysis.json') | ConvertFrom-Json
if ($result.complete_chains -ne 1) { throw 'Incomplete chains counted as complete' }
if ($result.observations[1].first_gap -ne 'GPUI mouse events to native click handler') { throw 'Missing click handler incorrectly attributed' }
if ($result.observations[2].first_gap -ne 'application handler to native application of update' -or $result.observations[2].native_update_applied -ne 0) { throw 'Missing native application was hidden' }
if ($result.observations[3].first_gap -ne 'applied update to expected state readback') { throw 'Incorrect state readback was accepted' }
Write-Output 'Trace analysis checks passed: complete chain, missing click, missing apply, and incorrect state.'
$dartFolder = Join-Path $folder 'dart'
New-Item -ItemType Directory -Force $dartFolder | Out-Null
@{ implementation = 'dart'; workload = 'cell'; run_id = 'synthetic'; inputs = $inputs } |
    ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dartFolder 'run.json') -Encoding UTF8
$nativeEvents = @(foreach ($sequence in 1..4) {
    foreach ($stage in @('gpui_mouse_down','gpui_mouse_up','native_click_handler')) { @{ sequence = $sequence; stage = $stage; data = @{} } }
    if ($sequence -le 2) { @{ sequence = $null; stage = 'update_applied'; data = @{ revision = $sequence + 1 } } }
})
$dartEvents = @(foreach ($sequence in 1..3) {
    @{ sequence = $sequence; stage = 'application_handler'; data = @{ update_ordinal = $sequence; target_revision = $sequence + 1 } }
    if ($sequence -eq 1) {
        @{ sequence = $sequence; stage = 'applied_acknowledged'; data = @{} }
        @{ sequence = $sequence; stage = 'state_observed'; data = @{ value = 'Tick 000001'; native = @{ value = 'Tick 000001' } } }
    }
})
$nativeEvents | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dartFolder 'native-input-trace.json') -Encoding UTF8
$dartEvents | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dartFolder 'application.json.input-trace.json') -Encoding UTF8
& "$PSScriptRoot/analyze-input.ps1" -Directory $dartFolder
$dartResult = Get-Content -Raw (Join-Path $dartFolder 'input-analysis.json') | ConvertFrom-Json
if ($dartResult.complete_chains -ne 1) { throw 'Dart stage correlation failed' }
if ($dartResult.observations[1].first_gap -ne 'native application of update to Dart acknowledgement') { throw 'Missing Dart acknowledgement incorrectly attributed' }
if ($dartResult.observations[2].first_gap -ne 'application handler to native application of update') { throw 'Missing native application incorrectly attributed' }
if ($dartResult.observations[3].first_gap -ne 'native click handler to application handler') { throw 'Missing application handler incorrectly attributed' }
Write-Output 'Dart trace checks passed: revision correlation and separate native/apply/acknowledgement gaps.'
