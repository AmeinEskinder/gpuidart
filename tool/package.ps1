param(
    [string]$CrtDirectory,
    [string]$EntryPoint = 'example/watchlist/main.dart',
    [ValidatePattern('^[a-zA-Z0-9_-]+$')][string]$Name = 'gpuidart'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    if (!(Test-Path -LiteralPath $EntryPoint -PathType Leaf)) { throw "Entry point not found: $EntryPoint" }
    if ($Name -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$') { throw "Reserved Windows application filename: $Name" }
    & "$PSScriptRoot/build.ps1" -Release
    $packageDirectory = Join-Path $projectRoot "build/$Name-windows-x64"
    New-Item -ItemType Directory -Path $packageDirectory -Force | Out-Null
    & dart compile exe '--define=gpuidart.packaged=true' -o "$packageDirectory/$Name.exe" $EntryPoint
    if ($LASTEXITCODE -ne 0) { throw 'Dart AOT compilation failed' }
    & mt.exe -nologo -manifest "$PSScriptRoot/windows/app.manifest" "-outputresource:$packageDirectory/$Name.exe;#1"
    if ($LASTEXITCODE -ne 0) { throw 'Could not embed executable DPI manifest' }
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
    Copy-Item -LiteralPath "$PSScriptRoot/windows/verify.ps1" -Destination "$packageDirectory/verify.ps1"
    (Get-Content -Raw -LiteralPath "$projectRoot/docs/windows-release-checks.md").Replace('gpuidart-windows-x64.zip', "$Name-windows-x64.zip").Replace('gpuidart.exe', "$Name.exe") |
        Set-Content -LiteralPath "$packageDirectory/RELEASE-CHECKS.md" -Encoding UTF8
    $applicationNotes = if ($EntryPoint.Replace('\','/') -eq 'example/watchlist/main.dart') {
        "Market watch has search, row selection, a shortlist and sample price updates.`r`nAll data is fictitious. No live market feed or trading connection is used.`r`n$Name.exe --self-test checks search, edits and shortlist transactions, prints JSON and closes."
    } else {
        "The application supplies its own --self-test behavior. The verifier expects one JSON result with mode set to aot and passed set to true. Adapt the example interaction checks to this application."
    }
    @'
GPUI-Dart Windows x64 SDK example

Run gpuidart.exe. Keep gpuidart.dll and vcruntime140.dll beside it.
No Dart SDK, source checkout or external assets are needed to launch.
Tested on Windows 11 x64. Close the window to exit.

{{APPLICATION_NOTES}}

In PowerShell, run ./verify.ps1 to check the package, loaded DLLs and display awareness.
For a freshly provisioned Windows VM: ./verify.ps1 -Environment clean_vm
The verification report records your environment declaration; it does not create a clean VM.
See RELEASE-CHECKS.md for the clean-machine and manual IME checks.

This private evaluation package uses GPUI Kit (Apache-2.0) and the Dart runtime.
vcruntime140.dll comes from Microsoft's release x64 Visual C++ redistributable.
See the source lockfiles for dependencies. This is an evaluation ZIP, not a signed installer.
'@.Replace('gpuidart.exe', "$Name.exe").Replace('{{APPLICATION_NOTES}}', $applicationNotes) | Set-Content -LiteralPath "$packageDirectory/README.txt" -Encoding UTF8

    $names = @("$Name.exe", 'gpuidart.dll', 'vcruntime140.dll', 'GPUI-Kit-LICENSE.txt', 'README.txt', 'verify.ps1', 'RELEASE-CHECKS.md')
    $files = foreach ($fileName in $names) {
        $path = Join-Path $packageDirectory $fileName
        [ordered]@{name=$fileName; bytes=(Get-Item -LiteralPath $path).Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    $sourcePaths = @(git ls-files --cached --others --exclude-standard -- lib native example tool pubspec.yaml pubspec.lock Cargo.toml Cargo.lock | Sort-Object -Unique)
    if ($LASTEXITCODE -ne 0) { throw 'Could not identify package source files' }
    $entryAbsolute = (Resolve-Path -LiteralPath $EntryPoint).ProviderPath
    $rootPrefix = "$projectRoot\"
    $entryTracked = $false
    $entrySourcePath = $entryAbsolute
    if ($entryAbsolute.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        $entrySourcePath = $entryAbsolute.Substring($rootPrefix.Length).Replace('\','/')
        $entryTracked = @(git ls-files --cached -- $entrySourcePath).Count -eq 1
    }
    if ($sourcePaths -notcontains $entrySourcePath) { $sourcePaths += $entrySourcePath }
    $sourcePaths = @($sourcePaths | Sort-Object -Unique)
    $applicationEntry = [ordered]@{
        path=$entrySourcePath; tracked_in_sdk_repository=$entryTracked
        sha256=(Get-FileHash -LiteralPath $entryAbsolute -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sourceFiles = @($sourcePaths | ForEach-Object {
        [ordered]@{path=$_; sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()}
    })
    $sourceText = ($sourceFiles | ForEach-Object { "$($_.path):$($_.sha256)" }) -join "`n"
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $sourceHash = ([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($sourceText)))).Replace('-','').ToLowerInvariant() }
    finally { $hasher.Dispose() }
    $sourceStatus = @(git status --porcelain --untracked-files=normal -- lib native example tool pubspec.yaml pubspec.lock Cargo.toml Cargo.lock)
    $build = [ordered]@{
        git_commit = (git rev-parse HEAD).Trim(); source_dirty = ($sourceStatus.Count -gt 0 -or !$entryTracked)
        source_sha256 = $sourceHash; source_files = $sourceFiles
        application_entry = $applicationEntry
        dart = ((& dart --version) -join ' ').Trim(); rustc = ((& rustc --version) -join ' ').Trim()
        cargo = ((& cargo --version) -join ' ').Trim(); built_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    [ordered]@{architecture='windows-x64'; executable="$Name.exe"; entry_point=$EntryPoint; dpi_awareness='PerMonitorV2'; native_abi=1; kit_revision='21622a70efd25219d26aa459164878c4da9e39f8'; build=$build; files=@($files)} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$packageDirectory/manifest.json" -Encoding UTF8
    $paths = @($names + 'manifest.json' | ForEach-Object { Join-Path $packageDirectory $_ })
    Compress-Archive -LiteralPath $paths -DestinationPath "build/$Name-windows-x64.zip" -CompressionLevel Optimal -Force
    Get-Item -LiteralPath "build/$Name-windows-x64.zip" | Select-Object FullName, Length
} finally { Pop-Location }
