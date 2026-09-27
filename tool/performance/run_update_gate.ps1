# Runs the snapshot gate at a baseline revision and at this working tree, each
# with its own release artifacts, and summarizes both. The baseline is a
# separate checkout (for example `git worktree add --detach PATH REVISION`).
# Windows only; Unix builds also need the launcher package.
#
#   ./tool/performance/run_update_gate.ps1 -Baseline C:\path\to\baseline -Output build\update-gate
#
# The gate compiles a Dart AOT capture from each tree, so each side runs its
# own SDK code against its own native library. Sides run one after the other,
# three repetitions each with rotated sizes, as run_snapshot_gate.dart does.
param(
    [Parameter(Mandatory = $true)] [string] $Baseline,
    [Parameter(Mandatory = $true)] [string] $Output,
    [string] $TargetDir = '',
    [string[]] $Sides = @('trunk', 'head')
)
$ErrorActionPreference = 'Stop'
$head = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path $Output | Out-Null

# Each side sources its own env.ps1. Restore the process environment between
# sides: a PATH holding both SDK directories makes `where.exe fxc.exe` print
# two lines, which the GPUI build script takes as one path.
$environment = @{}
foreach ($name in 'PATH', 'INCLUDE', 'LIB', 'CC', 'CXX', 'AR', 'CARGO_HOME', 'RUSTUP_HOME', 'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER') {
    $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$candidates = @(
    @{ name = 'trunk'; root = [IO.Path]::GetFullPath($Baseline) },
    @{ name = 'head'; root = $head }
)
foreach ($side in $candidates) {
    if ($Sides -notcontains $side.name) { continue }
    if (Test-Path -LiteralPath (Join-Path $Output $side.name)) { throw "Retain the previous $($side.name) series in $Output" }
    foreach ($entry in $environment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    Push-Location $side.root
    try {
        . ./tool/env.ps1
        if ($TargetDir) { $env:CARGO_TARGET_DIR = $TargetDir }
        $target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $side.root 'target' }
        & cargo build --locked --release -p gpuidart
        if ($LASTEXITCODE -ne 0) { throw "Release build failed for $($side.name)" }
        & cargo build --locked --release -p gpuidart-launcher
        if ($LASTEXITCODE -ne 0) { throw "Launcher build failed for $($side.name)" }
        $native = Join-Path $Output "$($side.name)-native"
        New-Item -ItemType Directory -Force -Path $native | Out-Null
        Copy-Item -LiteralPath (Join-Path $target 'release/gpuidart.dll') -Destination $native
        Copy-Item -LiteralPath (Join-Path $target 'release/gpuidart-launcher.exe') -Destination $native
        & git rev-parse HEAD | Out-File -Encoding utf8 (Join-Path $native 'source.txt')
        & git status --porcelain | Out-File -Encoding utf8 -Append (Join-Path $native 'source.txt')
        & dart run tool/performance/run_snapshot_gate.dart (Join-Path $Output $side.name) $native
        if ($LASTEXITCODE -ne 0) { throw "Gate failed for $($side.name)" }
        & dart run tool/performance/summarize_snapshot_gate.dart (Join-Path $Output $side.name) (Join-Path $Output "$($side.name)-summary.json")
        if ($LASTEXITCODE -ne 0) { throw "Summary failed for $($side.name)" }
    } finally {
        Pop-Location
    }
}
Write-Output "Gate series complete: $Output"
