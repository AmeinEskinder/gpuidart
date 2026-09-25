$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. ./tool/env.ps1
$kitRevision = '21622a70efd25219d26aa459164878c4da9e39f8'
if (-not (Test-Path .cache/gpui-kit/Cargo.toml)) {
    git clone https://github.com/longbridge/gpui-kit .cache/gpui-kit
    if ($LASTEXITCODE) { throw 'GPUI Kit clone failed' }
    git -C .cache/gpui-kit checkout --detach $kitRevision
    if ($LASTEXITCODE) { throw 'GPUI Kit checkout failed' }
}
if ((git -C .cache/gpui-kit rev-parse HEAD) -ne $kitRevision) { throw 'Benchmark requires the pinned GPUI Kit checkout' }
if (git -C .cache/gpui-kit status --porcelain --untracked-files=no) { throw 'GPUI Kit reference source has local edits' }
& cargo build --locked --release -p gpuidart -p gpui-native-comparison
if ($LASTEXITCODE) { throw 'Native comparison build failed' }
& cargo build --locked --release --manifest-path .cache/gpui-kit/Cargo.toml --target-dir target -p gpui-component-shell
if ($LASTEXITCODE) { throw 'Shell comparison build failed' }
New-Item -ItemType Directory -Force build | Out-Null
& dart compile exe benchmarks/dart/main.dart -o build/gpui-dart-comparison.exe
if ($LASTEXITCODE) { throw 'Dart comparison compilation failed' }
Push-Location benchmarks/solid
try {
    & bun install --frozen-lockfile
    if ($LASTEXITCODE) { throw 'Solid dependency installation failed' }
    & bun run check
    if ($LASTEXITCODE) { throw 'Solid type check failed' }
    & bun run build
    if ($LASTEXITCODE) { throw 'Solid comparison compilation failed' }
} finally { Pop-Location }
& "$PSScriptRoot/package.ps1"
