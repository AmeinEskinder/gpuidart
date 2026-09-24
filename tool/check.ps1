. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    & cargo fmt --check
    if ($LASTEXITCODE -ne 0) { throw 'Rust formatting failed' }
    & cargo test --locked -p gpuidart
    if ($LASTEXITCODE -ne 0) { throw 'Native tests failed' }
    & cargo build --locked -p gpuidart
    if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
    & dart analyze
    if ($LASTEXITCODE -ne 0) { throw 'Dart analysis failed' }
    & dart test
    if ($LASTEXITCODE -ne 0) { throw 'Dart integration test failed' }
} finally { Pop-Location }
