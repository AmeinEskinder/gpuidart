import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

String timestamp() => DateTime.now().toUtc().toIso8601String();

Future<void> writeJson(String path, Object value) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

Future<Map<String, dynamic>> readJson(String path) async =>
    jsonDecode((await File(path).readAsString()).replaceFirst('\ufeff', ''))
        as Map<String, dynamic>;

Future<String> fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Map<String, String> options(
  List<String> arguments,
  Set<String> names, {
  Set<String> flags = const {},
}) {
  final result = <String, String>{};
  for (final argument in arguments) {
    final match = RegExp(r'^--([a-z-]+)(?:=(.*))?$').firstMatch(argument);
    if (match == null || !names.contains(match[1])) {
      throw ArgumentError('Unknown option $argument');
    }
    final name = match[1]!;
    final value = match[2];
    if (flags.contains(name)) {
      if (value != null) {
        throw ArgumentError('--$name is a flag and does not accept a value');
      }
    } else if (value == null || value.isEmpty) {
      throw ArgumentError('--$name requires a value: --$name=VALUE');
    }
    result[name] = value ?? 'true';
  }
  return result;
}

Future<ProcessResult> runTimed(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    includeParentEnvironment: environment == null,
  );
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.transform(utf8.decoder).join();
  unawaited(output.catchError((Object _) => ''));
  unawaited(errors.catchError((Object _) => ''));
  var exited = false;
  unawaited(process.exitCode.then((_) => exited = true));
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProcessResult(process.pid, code, await output, await errors);
  } finally {
    // taskkill follows child processes too, including a timed-out verifier's app.
    if (!exited && Platform.isWindows) {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
    } else if (!exited) {
      process.kill();
    }
    await process.exitCode;
    await Future.wait([output, errors]);
  }
}
