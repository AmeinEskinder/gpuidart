import 'dart:convert';
import 'dart:io';

import '../src/dev_session.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Supply native executable and report path');
  }
  final temporary = await Directory.systemTemp.createTemp(
    'gpuidart-platform-reload-',
  );
  final entry = File('${temporary.path}/main.dart');
  final source = await File('tool/platform_probe/companion.dart')
      .readAsString();
  final changed = source.replaceFirst("=> 'probe-before'", "=> 'probe-after'");
  if (source == changed) throw StateError('Probe label marker not found');
  final report = <String, Object?>{
    'passed': false,
    'os': Platform.operatingSystem,
  };
  DevSession? session;
  try {
    await entry.writeAsString(source);
    session = await DevSession.start(
      entry: entry.path,
      arguments: [args.first, '--serve'],
    );
    final before = await session.call('inspect');
    report['before'] = before;
    await entry.writeAsString(changed);
    report['reload'] = await session.reload();
    final after = await session.call('inspect');
    report['after'] = after;
    if (before['applied']['label'] != 'probe-before' ||
        after['applied']['label'] != 'probe-after') {
      throw StateError('Changed application method did not reach native UI');
    }
    for (final key in ['native_pid', 'input_entity', 'input_value']) {
      if (before['applied'][key] != after['applied'][key]) {
        throw StateError('Reload changed retained $key');
      }
    }
    if (before['dart_pid'] != after['dart_pid']) {
      throw StateError('Dart process restarted');
    }
    await entry.writeAsString('invalid source for rejection probe');
    var rejected = false;
    try {
      await session.reload();
    } on StateError {
      rejected = true;
    }
    if (!rejected) throw StateError('Invalid source was accepted');
    report['invalid_source_rejected'] = true;
    report['after_invalid'] = await session.call('inspect');
    await entry.writeAsString(changed);
    report['recovery'] = await session.reload();
    // The native resize is deliberately delayed; permit it to render before close.
    await Future<void>.delayed(const Duration(seconds: 1));
    await session.close();
    final status = await session.process.exitCode;
    report['exit_code'] = status;
    if (status != 0) throw StateError('Companion parent exited $status');
    report['passed'] = true;
  } catch (error) {
    report['error'] = error.toString();
    exitCode = 1;
  } finally {
    await session?.close();
    File(args.last)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    // The directory was created above, never accepted from a caller.
    await temporary.delete(recursive: true);
  }
}
