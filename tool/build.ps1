param([switch]$Release)
. "$PSScriptRoot/env.ps1"
Push-Location $projectRoot
try {
    $buildArgs = @('build', '--locked', '-p', 'gpuidart')
    if ($Release) { $buildArgs += '--release' }
    & cargo @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Native build failed' }
    & dart pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dart dependency resolution failed' }
} finally { Pop-Location }

