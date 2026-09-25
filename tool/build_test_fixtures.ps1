. "$PSScriptRoot/env.ps1"
New-Item -ItemType Directory -Path "$projectRoot/.cache" -Force | Out-Null
& rustc --edition=2024 --crate-type cdylib -A private_interfaces "$projectRoot/test/fixtures/fault_host.rs" -o "$projectRoot/.cache/fault_host.dll"
if ($LASTEXITCODE -ne 0) { throw 'Native fault fixture build failed' }
