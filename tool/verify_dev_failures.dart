import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';
import 'src/windows_powershell.dart';

Future<void> main() async {
  final fixture = await Directory('.cache').createTemp('launcher-failures-');
  final entry = File('${fixture.path}/main.dart');
  await entry.writeAsString('''
import 'dart:async';
import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/development.dart';
Future<void> main(List<String> args) async {
  final host = await GpuiHost.openView(() => const UiText('text', 'Startup check'));
  if (args.first == 'late') {
    await Future<void>.delayed(const Duration(seconds: 2));
    registerGpuiReload(host);
  }
  await host.done;
}
''');
  final late = await DevSession.start(
    entry: entry.path,
    arguments: ['late'],
    startupTimeout: const Duration(seconds: 8),
  );
  await late.reload();
  await late.close();
  await late.close();

  final results = <String, Object>{
    'delayed_registration': 'passed',
    'reload_after_delayed_registration': 'passed',
    'repeated_close': 'passed',
  };
  for (final mode in ['no-registration', 'invalid-source']) {
    if (mode == 'invalid-source') {
      await entry.writeAsString('invalid Dart code');
    }
    final timer = Stopwatch()..start();
    Object? failure;
    DevSession? unexpected;
    try {
      unexpected = await DevSession.start(
        entry: entry.path,
        arguments: [mode],
        startupTimeout: const Duration(seconds: 3),
      );
    } catch (error) {
      failure = error;
    } finally {
      await unexpected?.close();
    }
    if (failure == null || timer.elapsed > const Duration(seconds: 10)) {
      throw StateError('$mode did not fail within the startup limit');
    }
    results[mode] = {
      'error': '$failure',
      'elapsed_ms': timer.elapsedMilliseconds,
    };
  }
  final needle = fixture.absolute.path.replaceAll("'", "''");
  final processes = await runWindowsPowerShell([
    '-NoProfile',
    '-Command',
    "@(Get-CimInstance Win32_Process | Where-Object { \$_.Name -match '^dart(vm)?\\.exe\$' -and \$_.CommandLine -like '*$needle*' }).Count",
  ]);
  if (processes.exitCode != 0 || '${processes.stdout}'.trim() != '0') {
    throw StateError(
      'Launcher left test processes behind: ${processes.stdout} ${processes.stderr}',
    );
  }
  results['remaining_application_processes'] = 0;
  results['passed'] = true;
  await Directory('reports/sdk').create(recursive: true);
  await File(
    'reports/sdk/development.json',
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(results)}\n');
  stdout.writeln(
    'PASS: delayed registration, reload, startup failures and child-process cleanup.',
  );
}
