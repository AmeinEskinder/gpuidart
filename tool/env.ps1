$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
# A worktree may junction .tools to the primary checkout. rustc rejects a
# sysroot reached through a junction, so resolve to the real directory.
$tools = Join-Path $projectRoot '.tools'
$toolsItem = Get-Item -LiteralPath $tools -ErrorAction SilentlyContinue
if ($toolsItem -and ($toolsItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $toolsItem.Target) {
    $tools = [string](@($toolsItem.Target)[0])
}
if (Test-Path -LiteralPath (Join-Path $tools 'cargo/bin/cargo.exe')) {
    $env:CARGO_HOME = Join-Path $tools 'cargo'
    $env:RUSTUP_HOME = Join-Path $tools 'rustup'
    $env:PATH = "$env:CARGO_HOME\bin;$env:PATH"
}
$msvcRoot = Join-Path $tools 'msvc'
if (Test-Path -LiteralPath (Join-Path $msvcRoot 'setup_x64.bat')) {
    $vc = (Get-ChildItem -LiteralPath (Join-Path $msvcRoot 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
    $sdk = Join-Path $msvcRoot 'Windows Kits/10'
    $sdkVersion = (Get-ChildItem -LiteralPath (Join-Path $sdk 'Lib') -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
    $env:PATH = "$vc\bin\Hostx64\x64;$sdk\bin\$sdkVersion\x64;$env:PATH"
    $env:INCLUDE = "$vc\include;$sdk\Include\$sdkVersion\ucrt;$sdk\Include\$sdkVersion\shared;$sdk\Include\$sdkVersion\um;$sdk\Include\$sdkVersion\winrt"
    $env:LIB = "$vc\lib\x64;$sdk\Lib\$sdkVersion\ucrt\x64;$sdk\Lib\$sdkVersion\um\x64"
    $env:CC = "$vc\bin\Hostx64\x64\cl.exe"
    $env:CXX = $env:CC
    $env:AR = "$vc\bin\Hostx64\x64\lib.exe"
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = "$vc\bin\Hostx64\x64\link.exe"
}
