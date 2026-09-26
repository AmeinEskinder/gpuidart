param(
    [string]$Zip = 'build/WatchlistMvp-windows-x64.zip',
    [ValidateSet('Enable', 'Disable')]
    [string]$VGpu = 'Enable'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$archivePath = if ([IO.Path]::IsPathRooted($Zip)) { $Zip } else { Join-Path $projectRoot $Zip }
$archive = (Resolve-Path -LiteralPath $archivePath).Path
$run = Join-Path $projectRoot ('build/release-checks/' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$inputDirectory = Join-Path $run 'input'
$outputDirectory = Join-Path $run 'results'
New-Item -ItemType Directory -Path $inputDirectory,$outputDirectory | Out-Null
Copy-Item -LiteralPath $archive -Destination (Join-Path $inputDirectory 'candidate.zip')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows/sandbox_release_check.ps1') -Destination $inputDirectory
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows/ime-results.md') -Destination (Join-Path $outputDirectory 'ime-results.md')
$identity = [ordered]@{
    prepared_at_utc = [DateTime]::UtcNow.ToString('o')
    original_archive = $archive
    zip_sha256 = (Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant()
    host_uuid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
    vgpu = $VGpu
}
$identity | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $inputDirectory 'candidate.json') -Encoding UTF8
$inputXml = [Security.SecurityElement]::Escape($inputDirectory)
$outputXml = [Security.SecurityElement]::Escape($outputDirectory)
@"
<Configuration>
  <VGpu>$VGpu</VGpu>
  <Networking>Disable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder><HostFolder>$inputXml</HostFolder><SandboxFolder>C:\GPUI-Input</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>$outputXml</HostFolder><SandboxFolder>C:\GPUI-Results</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\GPUI-Input\sandbox_release_check.ps1</Command></LogonCommand>
</Configuration>
"@ | Set-Content -LiteralPath (Join-Path $run 'check.wsb') -Encoding UTF8
@"
GPUI-Dart clean Windows check

Double-click check.wsb after enabling Windows Sandbox and completing any required restart.
The guest runs the existing packaged verifier automatically. Watch results/status.json.
Keep the Sandbox open until status is passed or failed. The output remains on the host.
Input is read-only. Only this run's results folder is writable. No SDK or network is supplied.
Virtual GPU sharing: $VGpu. Disable uses software rendering.
This checks packaging, not physical-GPU performance.
Candidate SHA-256: $($identity.zip_sha256)

For the manual screen check, open the extracted GPUI Dart candidate folder on the guest desktop.
Launch the executable named in manifest.json. Follow RELEASE-CHECKS.md.
This automated run does not claim human IME verification.
"@ | Set-Content -LiteralPath (Join-Path $run 'README.txt') -Encoding UTF8
Write-Output $run
