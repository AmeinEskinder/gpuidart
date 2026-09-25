$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. ./tool/env.ps1
cargo build --locked --release -p gpuidart -p gpui-native-comparison --features gpuidart/benchmark-trace,gpui-native-comparison/benchmark-trace
if ($LASTEXITCODE) { throw 'Trace build failed' }
New-Item -ItemType Directory -Force build/comparison-trace | Out-Null
Copy-Item -LiteralPath target/release/gpuidart.dll -Destination build/comparison-trace/gpuidart.dll
Copy-Item -LiteralPath target/release/gpui-native-comparison.exe -Destination build/comparison-trace/gpui-native-comparison.exe
Copy-Item -LiteralPath build/comparison/rust/vcruntime140.dll -Destination build/comparison-trace/vcruntime140.dll
# Restore the ordinary binaries before any performance run can use them.
cargo build --locked --release -p gpuidart -p gpui-native-comparison
if ($LASTEXITCODE) { throw 'Regular build failed' }
dart compile exe benchmarks/dart/main.dart -o build/gpui-dart-comparison.exe
if ($LASTEXITCODE) { throw 'Dart AOT compilation failed' }
