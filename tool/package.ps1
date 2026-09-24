param([string]$CrtDirectory)
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/build.ps1" -Release
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    $packageDirectory = Join-Path $projectRoot 'build/windows-x64'
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    & dart compile exe '--define=gpuidart.packaged=true' -o "$packageDirectory/gpuidart.exe" example/main.dart
    if ($LASTEXITCODE -ne 0) { throw 'Dart AOT compilation failed' }
    Copy-Item -LiteralPath 'target/release/gpuidart.dll' -Destination $packageDirectory

    $crtTarget = Join-Path $packageDirectory 'vcruntime140.dll'
    $crtArchive = Join-Path $projectRoot '.tools/downloads/Microsoft.VC.14.44.17.14.CRT.Redist.X64.base.vsix'
    if ($CrtDirectory) {
        Copy-Item -LiteralPath (Join-Path $CrtDirectory 'vcruntime140.dll') -Destination $crtTarget
    } elseif (Test-Path -LiteralPath $crtArchive) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($crtArchive)
        try {
            $entry = $archive.Entries | Where-Object { $_.FullName -match '/x64/Microsoft\.VC143\.CRT/vcruntime140\.dll$' }
            if (@($entry).Count -ne 1) { throw 'Expected one release x64 CRT entry' }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $crtTarget, $true)
        } finally { $archive.Dispose() }
    } else {
        throw 'Supply -CrtDirectory with the Microsoft Visual C++ x64 redistributable directory.'
    }

    $dependencies = & cargo metadata --locked --offline --filter-platform x86_64-pc-windows-msvc --format-version 1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Could not read dependency metadata' }
    $kit = $dependencies.packages | Where-Object { $_.name -eq 'gpui-kit' }
    $kitRoot = Split-Path (Split-Path (Split-Path $kit.manifest_path -Parent) -Parent) -Parent
    Copy-Item -LiteralPath (Join-Path $kitRoot 'LICENSE-APACHE') -Destination "$packageDirectory/GPUI-Kit-LICENSE.txt"
    @'
GPUI-Dart Windows x64 prototype

Run gpuidart.exe. Keep gpuidart.dll and vcruntime140.dll beside it.
No Dart SDK, source checkout or external assets are needed to launch.
Tested on Windows 11 x64. Close the window to exit.

gpuidart.exe --self-test: open a window, verify repaints and updates, print JSON, close.
gpuidart.exe --measure: measure 120 whole-view updates with 10,000 table rows.

This private evaluation package uses GPUI Kit (Apache-2.0) and the Dart runtime.
vcruntime140.dll comes from Microsoft's release x64 Visual C++ redistributable.
See the source lockfiles for dependencies. This is an evaluation ZIP, not a signed installer.
'@ | Set-Content -LiteralPath "$packageDirectory/README.txt" -Encoding UTF8

    $names = @('gpuidart.exe', 'gpuidart.dll', 'vcruntime140.dll', 'GPUI-Kit-LICENSE.txt', 'README.txt')
    $files = foreach ($name in $names) {
        $path = Join-Path $packageDirectory $name
        [ordered]@{name=$name; bytes=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    [ordered]@{architecture='windows-x64'; kit_revision='21622a70efd25219d26aa459164878c4da9e39f8'; files=@($files)} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$packageDirectory/manifest.json" -Encoding UTF8
    $paths = @($names + 'manifest.json' | ForEach-Object { Join-Path $packageDirectory $_ })
    Compress-Archive -LiteralPath $paths -DestinationPath 'build/gpuidart-windows-x64.zip' -CompressionLevel Optimal -Force
    Get-Item -LiteralPath 'build/gpuidart-windows-x64.zip' | Select-Object FullName, Length
} finally { Pop-Location }
