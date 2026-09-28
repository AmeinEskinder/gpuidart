param(
    [Parameter(Mandatory)][string]$RunPrefix,
    [ValidateRange(1,100)][int]$Repetitions = 3,
    [ValidateRange(2,120)][int]$Seconds = 10,
    [ValidateSet('rust','dart','solid','shell','flutter')][string[]]$Implementations = @('rust','dart'),
    [ValidateRange(1,10)][int]$AttemptsPerSlot = 3
)
# Completes a suite.ps1 series after interruptions. Every (repetition,
# implementation, workload) slot that has no run.json yet, in the series'
# rotated order, is run again under a retry run ID; interrupted attempts keep
# their failure.json. Rerunning this script is idempotent: finished slots are
# skipped, and a slot that keeps failing stops after $AttemptsPerSlot tries so
# the rest of the series can still complete.
$ErrorActionPreference = 'Stop'
if (@($Implementations | Select-Object -Unique).Count -ne $Implementations.Count) { throw 'Implementations must be distinct' }
$root = Split-Path -Parent $PSScriptRoot
$reports = Join-Path $root 'reports/comparison'
$incomplete = [Collections.Generic.List[string]]::new()
for ($repeat = 0; $repeat -lt $Repetitions; $repeat++) {
    for ($index = 0; $index -lt $Implementations.Count; $index++) {
        $implementation = $Implementations[($index + $repeat) % $Implementations.Count]
        foreach ($workload in @('idle','scroll','cell','burst')) {
            $slot = "$implementation-$workload"
            $attempts = @(Get-ChildItem -LiteralPath $reports -Directory | Where-Object { $_.Name -eq "$RunPrefix-$repeat" -or $_.Name -like "$RunPrefix-$repeat-retry*" } | ForEach-Object { Join-Path $_.FullName $slot } | Where-Object { Test-Path -LiteralPath $_ })
            if ($attempts | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'run.json') }) { continue }
            $tries = 0
            while ($tries -lt $AttemptsPerSlot) {
                $existing = @(Get-ChildItem -LiteralPath $reports -Directory | Where-Object { $_.Name -eq "$RunPrefix-$repeat" -or $_.Name -like "$RunPrefix-$repeat-retry*" } | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $slot) })
                $runId = if (-not $existing.Count) { "$RunPrefix-$repeat" } else { "$RunPrefix-$repeat-retry$($existing.Count)" }
                Write-Output "Running $slot repetition $repeat as $runId"
                & powershell -NoProfile -File "$PSScriptRoot/run.ps1" -Implementation $implementation -Workload $workload -RunId $runId -Seconds $Seconds
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 2) { break }
                $tries++
                Start-Sleep -Seconds 2
            }
            if ($tries -ge $AttemptsPerSlot) { $incomplete.Add("$slot repetition $repeat") }
        }
    }
}
if ($incomplete.Count) { Write-Warning ("Incomplete after $AttemptsPerSlot attempts each: " + ($incomplete -join '; ')) ; exit 3 }
Write-Output "Series $RunPrefix complete: $Repetitions repetitions of $($Implementations -join ', ')."
