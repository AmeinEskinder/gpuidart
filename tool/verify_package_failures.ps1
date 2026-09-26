param(
    [string]$Zip = 'build/WatchlistMvp-windows-x64.zip',
    [string]$ReportPath = 'reports/sdk/package-failures.json'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $fixture = Join-Path $projectRoot ('.cache/package-failures-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $fixture | Out-Null
    function Assert-RejectedPackage([string]$Directory, [string]$Expected) {
        $report = Join-Path $Directory 'verification.json'
        '{"passed":true}' | Set-Content -LiteralPath $report -Encoding UTF8
        $process = Start-Process powershell.exe -WindowStyle Hidden -PassThru -Wait -ArgumentList @(
            '-NoProfile', '-File', ('"' + (Join-Path $Directory 'verify.ps1') + '"'),
            '-ReportPath', ('"' + $report + '"')
        ) -RedirectStandardOutput (Join-Path $Directory 'verification.stdout.log') -RedirectStandardError (Join-Path $Directory 'verification.stderr.log')
        if ($process.ExitCode -eq 0) { throw 'Invalid package passed verification' }
        $result = Get-Content -Raw -LiteralPath $report | ConvertFrom-Json
        if ($result.passed -ne $false -or $result.error -notlike "*$Expected*") {
            throw "Failed verification left an incorrect report: $(Get-Content -Raw -LiteralPath $report)"
        }
        return $result
    }
    $tampered = Join-Path $fixture 'tampered'
    Expand-Archive -LiteralPath $Zip -DestinationPath $tampered
    $candidate = Get-Content -LiteralPath (Join-Path $tampered 'manifest.json') -Raw | ConvertFrom-Json
    $releaseChecks = Get-Content -LiteralPath (Join-Path $tampered 'RELEASE-CHECKS.md') -Raw
    if (!$releaseChecks.Contains("Launch $($candidate.executable) normally")) {
        throw 'Release instructions do not name the shipped executable'
    }
    Add-Content -LiteralPath (Join-Path $tampered 'README.txt') -Value 'Changed after packaging'
    $hashResult = Assert-RejectedPackage $tampered 'Package hash mismatch'

    $entry = Join-Path $fixture 'main.dart'
    @'
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:gpuidart/gpuidart.dart';
Future<void> main() async {
  final host = await GpuiHost.open(const UiText('text', 'Verifier negative case'));
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  const probe = '\u65e5\u672c\u8a9e \u00b7 caf\u00e9 \u{1f600}';
  stderr.writeln(probe);
  print(jsonEncode({'mode': 'aot', 'unicode': probe}));
  await host.close();
}
'@ | Set-Content -LiteralPath $entry -Encoding UTF8
    & "$PSScriptRoot/package.ps1" -EntryPoint $entry -Name MissingSelfTestResult | Out-Host
    $custom = Get-Content -LiteralPath 'build/MissingSelfTestResult-windows-x64/manifest.json' -Raw | ConvertFrom-Json
    $entryHash = (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash.ToLowerInvariant()
    if (!$custom.build.source_dirty -or $custom.build.application_entry.tracked_in_sdk_repository -or
        $custom.build.application_entry.sha256 -ne $entryHash -or
        @($custom.build.source_files | Where-Object sha256 -eq $entryHash).Count -ne 1) {
        throw 'Ignored custom entry source is missing from package identity'
    }
    $resultCheck = Assert-RejectedPackage (Join-Path $projectRoot 'build/MissingSelfTestResult-windows-x64') 'boolean passed true'
    $expectedUnicode = '"\u65e5\u672c\u8a9e \u00b7 caf\u00e9 \ud83d\ude00"' | ConvertFrom-Json
    if ($resultCheck.application.unicode -cne $expectedUnicode -or $resultCheck.stderr.Trim() -cne $expectedUnicode) {
        throw "Verifier corrupted UTF-8 stdout/stderr. See build/MissingSelfTestResult-windows-x64/verification.json"
    }
    [ordered]@{
        passed=$true; tampered_file_rejected=$hashResult; missing_self_test_result_rejected=$resultCheck
        stale_success_report_replaced=$true
        named_release_instructions=$true; ignored_entry_hashed=$true; ignored_entry_reported_uncommitted=$true
        unicode_stdout_and_stderr_preserved=$true
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
    Write-Output 'PASS: changed package contents and absent self-test success are rejected; failures replace stale success reports.'
} finally { Pop-Location }
