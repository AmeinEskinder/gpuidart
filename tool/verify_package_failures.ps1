param([string]$Zip = 'build/WatchlistMvp-windows-x64.zip')
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
    Add-Content -LiteralPath (Join-Path $tampered 'README.txt') -Value 'Changed after packaging'
    $hashResult = Assert-RejectedPackage $tampered 'Package hash mismatch'

    $entry = Join-Path $fixture 'main.dart'
    @'
import 'dart:async';
import 'dart:convert';
import 'package:gpuidart/gpuidart.dart';
Future<void> main() async {
  final host = await GpuiHost.open(const UiText('text', 'Verifier negative case'));
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  print(jsonEncode({'mode': 'aot'}));
  await host.close();
}
'@ | Set-Content -LiteralPath $entry -Encoding UTF8
    & "$PSScriptRoot/package.ps1" -EntryPoint $entry -Name MissingSelfTestResult | Out-Host
    $resultCheck = Assert-RejectedPackage (Join-Path $projectRoot 'build/MissingSelfTestResult-windows-x64') 'boolean passed true'
    [ordered]@{
        passed=$true; tampered_file_rejected=$hashResult; missing_self_test_result_rejected=$resultCheck
        stale_success_report_replaced=$true
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath 'reports/sdk/package-failures.json' -Encoding UTF8
    Write-Output 'PASS: changed package contents and absent self-test success are rejected; failures replace stale success reports.'
} finally { Pop-Location }
