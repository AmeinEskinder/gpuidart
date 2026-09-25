param(
    [string]$InputDirectory = 'C:\GPUI-Input',
    [string]$OutputDirectory = 'C:\GPUI-Results'
)
$ErrorActionPreference = 'Stop'
$statusPath = Join-Path $outputDirectory 'status.json'
$status = [ordered]@{ started_at_utc = [DateTime]::UtcNow.ToString('o'); status = 'running'; passed = $false }
$status | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
try {
    $identity = Get-Content -Raw -LiteralPath (Join-Path $inputDirectory 'candidate.json') | ConvertFrom-Json
    $system = Get-CimInstance Win32_ComputerSystem
    $uuid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
    if ($env:USERNAME -ne 'WDAGUtilityAccount' -or $system.Model -ne 'Virtual Machine' -or $uuid -eq $identity.host_uuid) {
        throw 'This runner requires a Windows Sandbox guest distinct from the preparation host.'
    }
    $archive = Join-Path $inputDirectory 'candidate.zip'
    $hash = (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($hash -ne $identity.zip_sha256) { throw 'Candidate ZIP hash differs from prepared identity.' }
    $sdkCommands = @(Get-Command dart,flutter,rustc,cargo,cl -ErrorAction SilentlyContinue | Select-Object Name,Source)
    $environment = [ordered]@{
        provisioning = 'Fresh Windows Sandbox, network disabled, virtual GPU, package and test script only'
        os = (Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,OSArchitecture)
        model = $system.Model; guest_uuid = $uuid; zip_sha256 = $hash
        developer_commands = $sdkCommands
        installed_languages = @(Get-InstalledLanguage | Select-Object LanguageId,LanguagePacks,LanguageFeatures)
    }
    $environment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputDirectory 'environment.json') -Encoding UTF8
    if ($sdkCommands.Count -ne 0) { throw 'Unexpected developer SDK commands in fresh guest.' }
    $packageDirectory = Join-Path ([Environment]::GetFolderPath('Desktop')) 'GPUI Dart candidate'
    New-Item -ItemType Directory -Path $packageDirectory | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $packageDirectory
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $packageDirectory 'verify.ps1') + '" -Environment clean_vm -ReportPath "' + (Join-Path $outputDirectory 'verification.json') + '"'
    $process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $outputDirectory 'verify.stdout.log') -RedirectStandardError (Join-Path $outputDirectory 'verify.stderr.log')
    try {
        $null = $process.Handle
        if (!$process.WaitForExit(120000)) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
            throw 'Packaged verifier exceeded two minutes.'
        }
        if ($process.ExitCode -ne 0) { throw "Packaged verifier exited $($process.ExitCode). See verify.stderr.log." }
    } finally { $process.Dispose() }
    $verification = Get-Content -Raw -LiteralPath (Join-Path $outputDirectory 'verification.json') | ConvertFrom-Json
    if ($verification.passed -isnot [bool] -or !$verification.passed) { throw 'Packaged verifier did not pass.' }
    $status.status = 'passed'
    $status.passed = $true
    $status['zip_sha256'] = $hash
    $status['human_ime'] = 'pending'
} catch {
    $status.status = 'failed'
    $status['error'] = $_.Exception.Message
} finally {
    $status['finished_at_utc'] = [DateTime]::UtcNow.ToString('o')
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statusPath -Encoding UTF8
}
if (!$status.passed) { exit 1 }
