import 'dart:convert';
import 'dart:io';

import '../../example/settings/app.dart';
import 'client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Usage: controls.dart REPORT.json');
  final file = File(args.single);
  if (file.existsSync()) throw StateError('Refusing to replace ${file.path}');
  file.parent.createSync(recursive: true);
  final steps = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'scope': 'External accessibility actions and state; no screen reader or visual claim.',
    'steps': steps,
    'passed': false,
  };
  SettingsApplication? app;
  try {
    app = await SettingsApplication.open();
    final settings = app;
    final process =
        (await app.host.diagnose('inspect'))['native_process_id'] as int;
    Future<Map<String, dynamic>> capture(
      String step,
      bool Function(List<dynamic>) ready,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      Map<String, dynamic>? last;
      do {
        await settings.idle;
        if (settings.failure != null) throw StateError('${settings.failure}');
        last = await platformQuery(process);
        if (ready(last['nodes'] as List)) {
          steps.add({'step': step, 'tree': last});
          return last;
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      } while (DateTime.now().isBefore(deadline));
      steps.add({'step': step, 'tree': last, 'failed': true});
      report['failed_frame_debug'] = await settings.host.diagnose('semantics');
      throw StateError('Platform state did not settle: $step');
    }

    dynamic named(List<dynamic> nodes, String name) => nodes
        .where(
          (n) =>
              n['name'] == name &&
              ![
                'ControlType.Text',
                'AXStaticText',
                'label',
                'static',
              ].contains(n['role']),
        )
        .singleOrNull;
    bool checked(dynamic n) =>
        n != null &&
        (n['checked'] == true || n['checked'] == 'On' || n['value'] == 1);
    await capture(
      'initial input and checkbox',
      (nodes) =>
          named(nodes, 'Display name')?['value'] == 'Dart user' &&
          checked(named(nodes, 'Enable workspace notifications')),
    );
    await platformQuery(
      process,
      operation: 'toggle',
      name: 'Enable workspace notifications',
    );
    await capture(
      'platform toggle reaches Dart',
      (nodes) =>
          !settings.draft.notifications &&
          !checked(named(nodes, 'Enable workspace notifications')),
    );
    await platformQuery(
      process,
      operation: 'set-value',
      name: 'Display name',
      id: 'name',
      value: 'Ada',
    );
    await capture(
      'platform text write reaches Dart',
      (nodes) =>
          settings.draft.name == 'Ada' &&
          named(nodes, 'Display name')?['value'] == 'Ada',
    );
    await platformQuery(process, operation: 'invoke', name: 'Appearance');
    await capture(
      'named select and slider',
      (nodes) =>
          named(nodes, 'Workspace accent') != null &&
          named(nodes, 'Preview spacing')?['min'] == 8,
    );
    await platformQuery(
      process,
      operation: 'set-range',
      name: 'Preview spacing',
      value: '22',
    );
    await capture('platform range write reaches Dart', (nodes) {
      final slider = named(nodes, 'Preview spacing');
      return settings.draft.spacing == 22 &&
          (slider?['number'] ?? slider?['value']) == 22;
    });
    await platformQuery(process, operation: 'invoke', name: 'Reset defaults');
    await capture(
      'named modal dialog',
      (nodes) => nodes.any(
        (n) =>
            ([
                  'ControlType.Window',
                  'AXDialog',
                  'AXSheet',
                  'dialog',
                ].contains(n['role']) ||
                n['subrole'] == 'AXDialog') &&
            n['name'] == 'Reset preferences?' &&
            (Platform.isMacOS || n['modal'] == true),
      ),
    );
    await platformQuery(process, operation: 'invoke', name: 'Keep editing');
    await capture(
      'platform cancel preserves draft',
      (nodes) =>
          settings.draft.spacing == 22 &&
          named(nodes, 'Preview spacing') != null &&
          settings.eventCounts['dialog_result'] == 1,
    );
    await platformQuery(process, operation: 'invoke', name: 'Reset defaults');
    await capture(
      'dialog reopens',
      (nodes) => named(nodes, 'Reset draft') != null,
    );
    await platformQuery(process, operation: 'invoke', name: 'Reset draft');
    await capture(
      'platform confirmation restores defaults',
      (nodes) =>
          settings.draft.spacing == 16 &&
          settings.eventCounts['dialog_result'] == 2 &&
          (named(nodes, 'Preview spacing')?['number'] ??
                  named(nodes, 'Preview spacing')?['value']) ==
              16,
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await app?.close();
    } catch (error) {
      report['close_error'] = '$error';
      report['passed'] = false;
      exitCode = 1;
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(
      'Saved ${file.path}: passed=${report['passed']}, steps=${steps.length}',
    );
  }
}
