$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
. ./tool/env.ps1
$packageRoot = Join-Path $root 'build/comparison'
New-Item -ItemType Directory -Force $packageRoot | Out-Null
$sourceFiles = [ordered]@{
    rust = @('target/release/gpui-native-comparison.exe')
    dart = @('build/gpui-dart-comparison.exe','target/release/gpuidart.dll')
    solid = @('benchmarks/solid/dist/gpui-solid-comparison.exe','benchmarks/solid/dist/gpuix-native.win32-x64-msvc.node')
    shell = @('target/release/gpui-component-shell.exe','benchmarks/shell/main.js')
}
$packages = foreach ($implementation in $sourceFiles.Keys) {
    $folder = Join-Path $packageRoot $implementation
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($source in $sourceFiles[$implementation]) { Copy-Item -LiteralPath (Join-Path $root $source) -Destination $folder }
    if (Test-Path -LiteralPath build/windows-x64/vcruntime140.dll) {
        Copy-Item -LiteralPath build/windows-x64/vcruntime140.dll -Destination $folder
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archivePath = Join-Path $root '.tools/downloads/Microsoft.VC.14.44.17.14.CRT.Redist.X64.base.vsix'
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            $entries = @($archive.Entries | Where-Object { $_.FullName -match '/x64/Microsoft\.VC143\.CRT/vcruntime140\.dll$' })
            if ($entries.Count -ne 1) { throw 'Expected one x64 release CRT entry in the redistributable archive' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entries[0], (Join-Path $folder 'vcruntime140.dll'), $true)
        } finally { $archive.Dispose() }
    }
    Copy-Item -LiteralPath .cache/gpui-kit/LICENSE-APACHE -Destination (Join-Path $folder 'GPUI-Kit-LICENSE.txt')
    $names = @($sourceFiles[$implementation] | ForEach-Object { Split-Path -Leaf $_ }) + @('vcruntime140.dll','GPUI-Kit-LICENSE.txt')
    $files = @($names | ForEach-Object {
        $file = Get-Item -LiteralPath (Join-Path $folder $_)
        @{ name = $file.Name; bytes = $file.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant() }
    })
    @{
        implementation = $implementation; files = $files
        payload_bytes = ($files | ForEach-Object { $_.bytes } | Measure-Object -Sum).Sum
        closure_status = 'explicit runtime payload; PE direct imports checked; clean-machine launch pending'
    }
}
$versions = @{
    rust = ((& .tools/cargo/bin/rustc.exe --version) -join '')
    dart = ((& dart --version 2>&1) -join '')
    bun = ((& bun --version) -join '')
    kit_revision = '21622a70efd25219d26aa459164878c4da9e39f8'
    gpui_pre = '0.3.6'; gpui_shell = '0.6.5'
    quickjs_jit_revision = '82d3808f3aa7d1c4ad2f360f5b3bd5979501d599'
    quickjs_jit_stdlib_revision = '605da483611a3548edb8c33fdff602e3f5f42076'
    gpuix_native = '0.10.0'; gpuix_solid = '0.10.0'; solid_js = '1.9.15'
    gpuix_binary_provenance = 'published npm artifact pinned by bun.lock integrity; upstream does not publish gitHead for this artifact'
    rust_build = 'cargo --release (optimized); profiler enabled for native reference and GPUI-Dart'
    solid_build = 'Bun compile + minify + Solid production plugin; npm Windows native addon'
    presentmon = '2.6.0'
    root_lock_sha256 = (Get-FileHash Cargo.lock).Hash
    shell_lock_sha256 = (Get-FileHash .cache/gpui-kit/Cargo.lock).Hash
    solid_lock_sha256 = (Get-FileHash benchmarks/solid/bun.lock).Hash
}
New-Item -ItemType Directory -Force reports/comparison | Out-Null
@{ versions = $versions; packages = @($packages); captured_utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 8 | Set-Content reports/comparison/artifacts.json -Encoding UTF8
Get-Item reports/comparison/artifacts.json | Select-Object FullName
