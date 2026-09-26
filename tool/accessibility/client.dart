import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// External OS accessibility client. It never substitutes the host's inspect
/// payload for a platform response. Failed clients retain stdout/stderr.
Future<Map<String, dynamic>> platformQuery(
  int process, {
  String operation = 'query',
  String name = '',
  String value = '',
  String id = '',
}) async {
  final (command, args) = switch (Platform.operatingSystem) {
    'windows' => (
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-File',
        'tool/accessibility/windows.ps1',
        '-AppProcessId',
        '$process',
        '-Operation',
        operation,
        if (name.isNotEmpty) ...['-Name', name],
        if (value.isNotEmpty) ...['-Value', value],
        if (id.isNotEmpty) ...['-Id', id],
      ],
    ),
    'linux' => (
      '/usr/bin/python3',
      ['tool/accessibility/linux.py', '$process', operation, name, value, id],
    ),
    'macos' => (
      'build/accessibility/ax-probe',
      ['$process', operation, name, value, id],
    ),
    _ => throw UnsupportedError('No platform accessibility probe'),
  };
  final child = await Process.start(command, args);
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  int status;
  try {
    status = await child.exitCode.timeout(const Duration(seconds: 20));
  } on TimeoutException {
    child.kill();
    await child.exitCode;
    throw StateError('Platform accessibility client timed out');
  }
  final text = await output;
  final error = await errors;
  if (status != 0) {
    throw StateError('Platform client exited $status: $error\n$text');
  }
  return jsonDecode(text) as Map<String, dynamic>;
}
