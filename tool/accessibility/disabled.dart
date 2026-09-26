import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import 'client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Usage: disabled.dart REPORT.json');
  final file = File(args.single);
  if (file.existsSync()) throw StateError('Refusing to replace ${file.path}');
  file.parent.createSync(recursive: true);
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'passed': false,
  };
  UiNode build(bool disabled) => UiColumn('form', [
    UiCheckbox('flag', 'Flag', checked: true, disabled: disabled),
    UiSlider(
      'range',
      min: 0,
      max: 10,
      step: 1,
      number: 5,
      disabled: disabled,
      semantics: const UiSemantics(label: 'Range'),
    ),
    UiSelect(
      'choice',
      options: [const UiSelectOption('one', 'One')],
      selected: 'one',
      disabled: disabled,
      semantics: const UiSemantics(label: 'Choice'),
    ),
    UiConfirmDialog(
      'confirm',
      'Confirm',
      title: 'Confirm?',
      message: 'Message',
      disabled: disabled,
    ),
  ]);
  GpuiHost? host;
  try {
    host = await GpuiHost.open(build(true));
    final process =
        (await host.diagnose('inspect'))['native_process_id'] as int;
    final changes = <Map<String, dynamic>>[];
    final subscription = host.events.listen((event) {
      if ([
        'checkbox_change',
        'slider_change',
        'select_change',
        'dialog_result',
      ].contains(event.type)) {
        changes.add(event.data);
      }
    });
    Future<Map<String, dynamic>> wait(bool enabled) async {
      Map<String, dynamic>? last;
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        last = await platformQuery(process);
        final nodes = last['nodes'] as List;
        if (['Flag', 'Range', 'Choice', 'Confirm'].every(
          (name) =>
              nodes
                  .where((n) => n['name'] == name && n['enabled'] == enabled)
                  .length ==
              1,
        )) {
          return last;
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      } while (DateTime.now().isBefore(deadline));
      throw StateError('Disabled metadata mismatch: $last');
    }

    report['disabled'] = await wait(false);
    final attempts = <Map<String, Object?>>[];
    for (final (name, op) in [
      ('Flag', 'toggle'),
      ('Range', 'set-range'),
      ('Confirm', 'invoke'),
    ]) {
      try {
        attempts.add({
          'name': name,
          'reply': await platformQuery(
            process,
            operation: op,
            name: name,
            value: '9',
          ),
        });
      } catch (error) {
        attempts.add({'name': name, 'rejected': '$error'});
      }
    }
    report['disabled_actions'] = attempts;
    report['after_actions'] = await wait(false);
    if (changes.isNotEmpty) {
      throw StateError('Disabled controls emitted changes: $changes');
    }
    await host.publish(build(false));
    report['enabled'] = await wait(true);
    await platformQuery(
      process,
      operation: 'set-range',
      name: 'Range',
      value: '9',
    );
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (changes.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (changes.length != 1 ||
        changes.single['type'] != 'slider_change' ||
        changes.single['number'] != 9) {
      throw StateError('Enabled slider action did not emit once: $changes');
    }
    report['events'] = changes;
    await subscription.cancel();
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await host?.close();
    } catch (error) {
      report['close_error'] = '$error';
      report['passed'] = false;
      exitCode = 1;
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('Saved ${file.path}: passed=${report['passed']}');
  }
}
