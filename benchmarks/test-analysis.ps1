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
