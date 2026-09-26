import 'dart:convert';
import 'dart:io';

/// Retains a command's output and status, including failed benchmark attempts.
Future<void> main(List<String> args) async {
  if (args.length < 2) {
    throw ArgumentError(
      'Usage: run_logged.dart NEW_DIRECTORY EXECUTABLE [ARGS...]',
    );
  }
  final output = Directory(args.first);
  if (output.existsSync()) {
    throw StateError('Retain the earlier attempt: ${output.path}');
  }
  output.createSync(recursive: true);
  final record = <String, Object?>{
    'command': args.sublist(1),
    'started_utc': DateTime.now().toUtc().toIso8601String(),
    'passed': false,
  };
  final timer = Stopwatch()..start();
  final out = File('${output.path}/stdout.log').openWrite();
  final err = File('${output.path}/stderr.log').openWrite();
  try {
    final process = await Process.start(args[1], args.sublist(2));
    record['pid'] = process.pid;
    final copies = [
      out.addStream(process.stdout),
      err.addStream(process.stderr),
    ];
    final status = await process.exitCode;
    await Future.wait(copies);
    record['exit_code'] = status;
    record['passed'] = status == 0;
    exitCode = status;
  } catch (error, stack) {
    record['error'] = '$error';
    record['stack'] = '$stack';
    exitCode = 1;
  } finally {
    await out.close();
    await err.close();
    record['elapsed_us'] = timer.elapsedMicroseconds;
    record['finished_utc'] = DateTime.now().toUtc().toIso8601String();
    await File(
      '${output.path}/result.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(record)}\n');
  }
  stdout.writeln('Saved ${output.path}: passed=${record['passed']}');
}
