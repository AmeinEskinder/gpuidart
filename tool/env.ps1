$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (Test-Path -LiteralPath "$projectRoot/.tools/cargo/bin/cargo.exe") {
    $env:CARGO_HOME = "$projectRoot/.tools/cargo"
    $env:RUSTUP_HOME = "$projectRoot/.tools/rustup"
    $env:PATH = "$env:CARGO_HOME/bin;$env:PATH"
}
$msvcRoot = "$projectRoot/.tools/msvc"
if (Test-Path -LiteralPath "$msvcRoot/setup_x64.bat") {
    $vc = (Get-ChildItem -LiteralPath "$msvcRoot/VC/Tools/MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
    $sdk = "$msvcRoot/Windows Kits/10"
    $sdkVersion = (Get-ChildItem -LiteralPath "$sdk/Lib" -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
    $env:PATH = "$vc/bin/Hostx64/x64;$sdk/bin/$sdkVersion/x64;$env:PATH"
    $env:INCLUDE = "$vc/include;$sdk/Include/$sdkVersion/ucrt;$sdk/Include/$sdkVersion/shared;$sdk/Include/$sdkVersion/um;$sdk/Include/$sdkVersion/winrt"
    $env:LIB = "$vc/lib/x64;$sdk/Lib/$sdkVersion/ucrt/x64;$sdk/Lib/$sdkVersion/um/x64"
    $env:CC = "$vc/bin/Hostx64/x64/cl.exe"
    $env:CXX = $env:CC
    $env:AR = "$vc/bin/Hostx64/x64/lib.exe"
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER = "$vc/bin/Hostx64/x64/link.exe"
}

