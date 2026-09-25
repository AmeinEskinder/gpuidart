$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $root ('.cache/comparison-analysis-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $folder | Out-Null
@{
    purpose = 'foreground measurement'; implementation = 'synthetic-test'; workload = 'scroll'
    process_id = 42; start_qpc = 100; end_qpc = 200
    input_deadlines_missed = 0; cpu_percent_one_core = 1; window_available_ms = 2
    process_samples = @(@{ working_set_bytes = 100; private_bytes = 200 })
} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $folder 'run.json') -Encoding UTF8
@'
CPUStartQPC,ProcessID,SwapChainAddress,DisplayedTime,MsBetweenPresents,MsBetweenDisplayChange,MsAllInputToPhotonLatency
90,42,1,16,1000,1000,1000
110,42,1,16,1000,1000,10
120,42,1,NA,10,NA,NA
140,42,1,16,20,30,12
160,42,1,16,20,20,11
170,99,2,16,500,500,500
210,42,1,16,500,500,500
'@ | Set-Content (Join-Path $folder 'present.csv') -Encoding UTF8
& "$PSScriptRoot/analyze.ps1" -Directory $folder
$result = Get-Content -Raw (Join-Path $folder 'analysis.json') | ConvertFrom-Json
if ($result.presentation.frames -ne 4) { throw 'Measurement window or process filtering failed' }
if ($result.presentation.frames_not_displayed -ne 1) { throw 'Dropped frame handling failed' }
if ($result.presentation.between_display_changes_ms.p95 -ne 30) { throw 'Warmup interval leaked into measured percentiles' }
if ($result.presentation.between_presents_ms.samples -ne 3) { throw 'First out-of-window interval was retained' }
if ($null -ne $result.presentation.input_to_response_present_ms) { throw 'Input association was incorrectly promoted to response latency' }
Write-Output 'Analysis checks passed: time/process boundaries, dropped frames, warmup exclusion, and unknown response latency.'
$lost = Join-Path $folder 'lost-update'
$interrupted = Join-Path $folder 'interrupted'
New-Item -ItemType Directory -Force $lost,$interrupted | Out-Null
@{
    purpose = 'foreground measurement'; implementation = 'lost-update'; workload = 'cell'
    input_count = 50; input_deadlines_missed = 0; cpu_percent_one_core = 2
    correctness = @{ passed = $false; expected_updates = 50; observed_updates = 49 }
    process_samples = @(@{ working_set_bytes = 100; private_bytes = 200 })
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $lost 'run.json') -Encoding UTF8
@{ implementation = 'interrupted'; workload = 'cell'; error = 'focus lost' } |
    ConvertTo-Json | Set-Content (Join-Path $interrupted 'failure.json') -Encoding UTF8
& "$PSScriptRoot/analyze.ps1" -Directory $folder
$observations = Get-Content -Raw (Join-Path $folder 'analysis.json') | ConvertFrom-Json
$lostObservation = $observations | Where-Object implementation -eq 'lost-update'
if ($lostObservation.equal_work_timing_eligible -or $lostObservation.correctness.observed_updates -ne 49 -or $lostObservation.cpu_percent_one_core -ne 2) { throw 'Lost updates were hidden or admitted to equal-work timing' }
if (@($observations | Where-Object implementation -eq 'interrupted').Count -ne 1) { throw 'Interrupted observation disappeared from the report' }
Write-Output 'Reliability checks passed: completed correctness failures and interrupted observations remain visible.'
$extra = Join-Path $folder 'extra-input'
New-Item -ItemType Directory -Force $extra | Out-Null
@{
    purpose = 'foreground measurement'; implementation = 'extra-input'; workload = 'cell'
    seconds_requested = 10; input_count = 51; input_deadlines_missed = 0
    correctness = @{ passed = $true; expected_updates = 51; observed_updates = 51 }
    process_samples = @()
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $extra 'run.json') -Encoding UTF8
& "$PSScriptRoot/analyze.ps1" -Directory $folder
$observations = Get-Content -Raw (Join-Path $folder 'analysis.json') | ConvertFrom-Json
$extraObservation = $observations | Where-Object implementation -eq 'extra-input'
if ($extraObservation.equal_work_timing_eligible -or $extraObservation.input_delivery.excess -ne 1 -or -not $extraObservation.correctness.passed) { throw 'Extra driver input was hidden or misclassified as application failure' }
Write-Output 'Delivery check passed: extra injected input is separate from application correctness.'
