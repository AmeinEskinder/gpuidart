param(
    [string]$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [ValidateRange(1,100)][int]$Repetitions = 3,
    [ValidateRange(2,120)][int]$Seconds = 10,
    [ValidateSet('rust','dart','solid','shell')][string[]]$Implementations = @('rust','shell','solid','dart'),
    [switch]$BackgroundSmoke,
    [switch]$CapturePresent
)
$ErrorActionPreference = 'Stop'
if (@($Implementations | Select-Object -Unique).Count -ne $Implementations.Count) { throw 'Implementations must be distinct' }
for ($repeat = 0; $repeat -lt $Repetitions; $repeat++) {
    # Rotate the order to distribute warm caches and time-of-run effects.
    for ($index = 0; $index -lt $implementations.Count; $index++) {
        $implementation = $implementations[($index + $repeat) % $implementations.Count]
        foreach ($workload in @('idle','scroll','cell','burst')) {
            $arguments = @('-NoProfile','-File',"$PSScriptRoot/run.ps1",'-Implementation',$implementation,'-Workload',$workload,'-RunId',"$RunId-$repeat",'-Seconds',$Seconds)
            if ($BackgroundSmoke) { $arguments += '-BackgroundSmoke' }
            if ($CapturePresent) { $arguments += '-CapturePresent' }
            & powershell @arguments
            if ($LASTEXITCODE -eq 2) { Write-Warning "Retained correctness failure at $implementation $workload repetition $repeat" }
            elseif ($LASTEXITCODE) { throw "Stopped at $implementation $workload repetition $repeat" }
        }
    }
}
