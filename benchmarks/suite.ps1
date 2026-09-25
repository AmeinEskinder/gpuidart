param([string]$RunId = (Get-Date -Format 'yyyyMMdd-HHmmss'), [int]$Repetitions = 3, [int]$Seconds = 10, [switch]$BackgroundSmoke, [switch]$CapturePresent)
$ErrorActionPreference = 'Stop'
$implementations = @('rust','shell','solid','dart')
for ($repeat = 0; $repeat -lt $Repetitions; $repeat++) {
    # Rotate the order to distribute warm caches and time-of-run effects.
    for ($index = 0; $index -lt $implementations.Count; $index++) {
        $implementation = $implementations[($index + $repeat) % $implementations.Count]
        foreach ($workload in @('idle','scroll','cell','burst')) {
            $arguments = @('-NoProfile','-File',"$PSScriptRoot/run.ps1",'-Implementation',$implementation,'-Workload',$workload,'-RunId',"$RunId-$repeat",'-Seconds',$Seconds)
            if ($BackgroundSmoke) { $arguments += '-BackgroundSmoke' }
            if ($CapturePresent) { $arguments += '-CapturePresent' }
            & powershell @arguments
            if ($LASTEXITCODE) { throw "Stopped at $implementation $workload repetition $repeat" }
        }
    }
}
