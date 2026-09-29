import 'dart:io';

import 'src/archives.dart';
import 'src/commands.dart';
import 'src/toolchain.dart';
import 'windows/common.dart';

Future<Map<String, dynamic>> rejectedPackage(
  Directory directory,
  String expected,
) async {
  final path = '${directory.path}/verification.json';
  await writeJson(path, {'passed': true});
  final process = await runTimed('${directory.path}/verify.exe', [
    '--report=$path',
  ]);
  await File('${directory.path}/verification.stdout.log')
      .writeAsString('${process.stdout}');
  await File('${directory.path}/verification.stderr.log')
      .writeAsString('${process.stderr}');
  if (process.exitCode == 0) {
    throw StateError('Invalid package passed verification');
  }
  final result = await readJson(path);
  if (result['passed'] != false || !'${result['error']}'.contains(expected)) {
    throw StateError('Failed verification left an incorrect report: $result');
  }
  return result;
}

Future<void> main(List<String> arguments) async {
  final args = options(arguments, {'zip', 'report'});
  final parent = await Directory('.cache').create(recursive: true);
  final fixture = await parent.createTemp('package-failures-');
  try {
    final tampered = Directory('${fixture.path}/tampered');
    await extractZip(
      File(args['zip'] ?? 'build/WatchlistMvp-windows-x64.zip'),
      tampered,
    );
    final candidate = await readJson('${tampered.path}/manifest.json');
    final instructions = await File('${tampered.path}/RELEASE-CHECKS.md')
        .readAsString();
    if (!instructions.contains('Launch ${candidate['executable']} normally')) {
      throw StateError(
        'Release instructions do not name the shipped executable',
      );
    }
    await File('${tampered.path}/README.txt')
        .writeAsString('Changed after packaging', mode: FileMode.append);
    final hashResult = await rejectedPackage(
      tampered.absolute,
      'Package hash mismatch',
    );
    final entry = File('${fixture.path}/main.dart');
    await entry.writeAsString(r'''
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
''');
    await command(dartExecutable, [
      'run',
      'tool/package.dart',
      '--entry=${entry.absolute.path}',
      '--name=MissingSelfTestResult',
    ]);
    final customDirectory = Directory('${fixture.path}/missing-result');
    await extractZip(
      File('build/MissingSelfTestResult-windows-x64.zip'),
      customDirectory,
    );
    final custom = await readJson('${customDirectory.path}/manifest.json');
    final build = custom['build'] as Map;
    final entryHash = await fileHash(entry);
    if (build['source_dirty'] != true ||
        build['application_entry']['tracked_in_sdk_repository'] != false ||
        build['application_entry']['sha256'] != entryHash ||
        (build['source_files'] as List)
                .where((file) => file['sha256'] == entryHash)
                .length !=
            1) {
      throw StateError(
        'Ignored custom entry source is missing from package identity',
      );
    }
    final resultCheck = await rejectedPackage(
      customDirectory.absolute,
      'boolean passed true',
    );
    const expectedUnicode = '日本語 · café 😀';
    if (resultCheck['application']['unicode'] != expectedUnicode ||
        (resultCheck['stderr'] as String).trim() != expectedUnicode) {
      throw StateError('Verifier corrupted UTF-8 stdout/stderr: $resultCheck');
    }
    await writeJson(args['report'] ?? 'reports/sdk/package-failures.json', {
      'passed': true,
      'tampered_file_rejected': hashResult,
      'missing_self_test_result_rejected': resultCheck,
      'stale_success_report_replaced': true,
      'named_release_instructions': true,
      'ignored_entry_hashed': true,
      'ignored_entry_reported_uncommitted': true,
      'unicode_stdout_and_stderr_preserved': true,
    });
    stdout.writeln(
      'PASS: changed package contents and absent self-test success are rejected; failures replace stale success reports.',
    );
  } finally {
    await fixture.delete(recursive: true);
  }
}
