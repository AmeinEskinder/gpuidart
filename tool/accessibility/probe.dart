import 'dart:convert';
import 'dart:io';

import '../../example/settings/app.dart';
import 'client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Usage: probe.dart REPORT.json');
  final file = File(args.single);
  if (file.existsSync()) throw StateError('Refusing to replace ${file.path}');
  file.parent.createSync(recursive: true);
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'time_utc': DateTime.now().toUtc().toIso8601String(),
    'scope': 'Pinned backend feasibility; external platform queries, not full SDK semantics acceptance.',
    'passed': false,
  };
  SettingsApplication? app;
  try {
    app = await SettingsApplication.open();
    final native = await app.host.diagnose('inspect');
    final process = native['native_process_id'] as int;
    report['native_process'] = process;
    Map<String, dynamic>? tree;
    for (var attempt = 0; attempt < 10; attempt++) {
      tree = await platformQuery(process);
      if ((tree['nodes'] as List).any((n) => n['name'] == 'Appearance')) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    report['general'] = tree;
    await platformQuery(process, operation: 'invoke', name: 'Appearance');
    for (var attempt = 0; attempt < 40; attempt++) {
      await app.idle;
      if (app.section == 'appearance') break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (app.section != 'appearance') {
      throw StateError('Platform Invoke did not reach the application');
    }
    await app.host.diagnose('repaint', {'frames': 2});
    report['appearance'] = await platformQuery(process);
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await app?.close();
    } catch (error, stack) {
      report['close_error'] = '$error';
      report['close_stack'] = '$stack';
      report['passed'] = false;
      exitCode = 1;
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('Saved ${file.path}: passed=${report['passed']}');
    // The report is an artifact; the log should say why a run failed too.
    if (report['error'] case final Object error)
      stdout.writeln('Error: $error');
    if (report['close_error'] case final Object error) {
      stdout.writeln('Close error: $error');
    }
  }
}
