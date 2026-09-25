import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'src/commands.dart';

Future<void> main(List<String> args) async {
  final runtimeOnly = args.contains('--runtime-only');
  args = args.where((arg) => arg != '--runtime-only').toList();
  if (args.isEmpty || args.length > 3) {
    throw ArgumentError(
      'Usage: verify_package.dart ARCHIVE [REPORT] [ENVIRONMENT] [--runtime-only]',
    );
  }
  final archive = File(args[0]).absolute;
  final report = File(
    args.length > 1 ? args[1] : 'build/package-verification.json',
  ).absolute;
  if (Platform.isWindows) {
    if (runtimeOnly) {
      throw UnsupportedError('--runtime-only is a Unix verifier option');
    }
    stdout.writeln(
      await command('powershell.exe', [
        '-NoProfile',
        '-File',
        'tool/verify_package.ps1',
        '-Zip',
        archive.path,
        '-ReportPath',
        report.path,
      ]),
    );
    return;
  }
  final directory = await Directory.systemTemp.createTemp(
    'gpuidart-extracted-',
  );
  // Extract our generated archive outside the repository. Keep evidence in place.
  final names = await command('tar', ['-tzf', archive.path]);
  if (names
      .split('\n')
      .any((name) => name.startsWith('/') || name.split('/').contains('..'))) {
    throw StateError('Unsafe archive path');
  }
  await command('tar', ['-xzf', archive.path, '-C', directory.path]);
  final result = await Process.run('${directory.path}/verify', [
    if (runtimeOnly) '--runtime-only',
    '--report=${report.path}',
    '--environment=${args.length > 2 ? args[2] : 'development_machine'}',
  ]);
  final value = jsonDecode(await report.readAsString()) as Map<String, dynamic>;
  value['archive'] = {
    'path': archive.path,
    'sha256': sha256.convert(await archive.readAsBytes()).toString(),
    'bytes': await archive.length(),
  };
  await report.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  exitCode = result.exitCode;
}
