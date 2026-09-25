$ErrorActionPreference = 'Stop'
$destination = Join-Path (Split-Path -Parent $PSScriptRoot) '.tools/presentmon/PresentMon.exe'
New-Item -ItemType Directory -Force (Split-Path -Parent $destination) | Out-Null
if (-not (Test-Path -LiteralPath $destination)) {
    Invoke-WebRequest 'https://github.com/GameTechDev/PresentMon/releases/download/v2.6.0/PresentMon-2.6.0-x64.exe' -OutFile $destination
}
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash -ne 'B2A706BC6AD475749E3B7E3409263AA1E6906D45BDCF993F6DBC0F660188F1AF') {
    throw 'PresentMon does not match the pinned 2.6.0 binary'
}
Write-Output $destination
