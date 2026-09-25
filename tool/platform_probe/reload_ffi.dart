import 'dart:convert';
import 'dart:io';

import '../src/dev_session.dart';

Future<void> main(List<String> args) async {
  final temporary = await Directory.systemTemp.createTemp(
    'gpuidart-platform-ffi-',
  );
  final entry = File('${temporary.path}/main.dart');
  final source = await File('tool/platform_probe/probe.dart').readAsString();
  final changed = source.replaceFirst('codeSignal() => 7', 'codeSignal() => 8');
  if (source == changed) throw StateError('Probe method marker not found');
  final report = <String, Object?>{'passed': false};
  DevSession? session;
  try {
    await entry.writeAsString(source);
    session = await DevSession.start(
      entry: entry.path,
      arguments: [args.first, '--serve'],
    );
    report['initial'] = await session.reload();
    final before = await session.call('inspect');
    report['before'] = before;
    await entry.writeAsString(changed);
    report['reload'] = await session.reload();
    final after = await session.call('inspect');
    report['after'] = after;
    if (before['signal'] != 7 ||
        after['signal'] != 8 ||
        before['pid'] != after['pid'] ||
        !(after['callbacks'] as List).contains(8)) {
      throw StateError(
        'Reload did not receive the changed code value from native',
      );
    }
    await entry.writeAsString('invalid source for rejection probe');
    var rejected = false;
    try {
      await session.reload();
    } on StateError {
      rejected = true;
    }
    if (!rejected) throw StateError('Invalid source accepted');
    report['invalid_source_rejected'] = true;
    await entry.writeAsString(changed);
    report['recovery'] = await session.reload();
    await Future<void>.delayed(const Duration(seconds: 1));
    await session.close();
    report['exit_code'] = await session.process.exitCode;
    if (report['exit_code'] != 0) throw StateError('FFI probe exit failed');
    report['passed'] = true;
  } catch (error) {
    report['error'] = error.toString();
    exitCode = 1;
  } finally {
    await session?.close();
    File(args.last)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    await temporary.delete(recursive: true);
  }
}
