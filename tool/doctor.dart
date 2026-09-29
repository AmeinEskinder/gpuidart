import 'dart:convert';
import 'dart:io';

import 'src/toolchain.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--json')) {
    throw ArgumentError('Usage: gpuidart doctor [--json]');
  }
  final environment = toolchainEnvironment();
  final checks = <Map<String, Object>>[];
  for (final tool in [
    dartExecutable,
    'cargo',
    'rustc',
    'git',
    if (Platform.isWindows) 'mt.exe',
    if (Platform.isWindows) 'cl.exe',
  ]) {
    final executable = toolExecutable(tool, environment);
    try {
      final result = await Process.run(
        executable,
        [
          switch (tool) {
            'mt.exe' => '-?',
            'cl.exe' => '/?',
            _ => '--version',
          },
        ],
        environment: environment,
        includeParentEnvironment: false,
      );
      final output = '${result.stdout}\n${result.stderr}'.trim();
      checks.add({
        'tool': tool,
        'path': executable,
        'passed': result.exitCode == 0,
        'output': output.split('\n').first,
      });
    } on ProcessException catch (error) {
      checks.add({
        'tool': tool,
        'path': executable,
        'passed': false,
        'error': error.message,
      });
    }
  }
  final passed = checks.every((check) => check['passed'] == true);
  if (args.contains('--json')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'passed': passed,
        'checks': checks,
      }),
    );
  } else {
    for (final check in checks) {
      stdout.writeln(
        '${check['passed'] == true ? 'OK' : 'MISSING'} ${check['tool']}: ${check['output'] ?? check['error']}',
      );
    }
  }
  if (!passed) exitCode = 1;
}
