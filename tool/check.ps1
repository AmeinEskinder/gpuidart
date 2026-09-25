param([switch]$Headless)
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    & cargo fmt --check
    if ($LASTEXITCODE -ne 0) { throw 'Rust formatting failed' }
    & rustfmt --edition 2024 --check test/fixtures/fault_host.rs
    if ($LASTEXITCODE -ne 0) { throw 'Fault fixture formatting failed' }
    & cargo test --locked -p gpuidart
    if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
    if (!$Headless) {
        & cargo build --locked -p gpuidart
        if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
    }
    & dart format --output=none --set-exit-if-changed lib test
    if ($LASTEXITCODE -ne 0) { throw 'Dart formatting failed' }
    & dart analyze --fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Dart analysis failed' }
    & "$PSScriptRoot/build_test_fixtures.ps1"
    if ($Headless) { & dart test --exclude-tags live-window }
    else { & dart test }
    if ($LASTEXITCODE -ne 0) { throw 'Dart integration test failed' }
} finally { Pop-Location }
