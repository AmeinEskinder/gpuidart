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
  final timer = Stopwatch()..start();
  final restarts = <String>[];
  while (true) {
    final remaining = const Duration(seconds: 20) - timer.elapsed;
    if (remaining <= Duration.zero) {
      throw StateError('Platform query deadline expired; restarts=$restarts');
    }
    final child = await Process.start(command, args);
    final output = child.stdout.transform(utf8.decoder).join();
    final errors = child.stderr.transform(utf8.decoder).join();
    int status;
    try {
      status = await child.exitCode.timeout(remaining);
    } on TimeoutException {
      child.kill();
      await child.exitCode;
      throw StateError(
        'Platform accessibility client timed out; restarts=$restarts',
      );
    }
    final text = await output;
    final error = await errors;
    if (status == 75 &&
        Platform.isLinux &&
        operation == 'query' &&
        restarts.length < 4) {
      restarts.add(error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      continue;
    }
    if (status != 0) {
      throw StateError(
        'Platform client exited $status: $error\n$text\nrestarts=$restarts',
      );
    }
    final result = jsonDecode(text) as Map<String, dynamic>;
    if (Platform.isLinux) result['query_restarts'] = restarts;
    if (error.isNotEmpty) result['client_stderr'] = error;
    return result;
  }
}

/// Platform names asserted against responses, rather than inferred from SDK IDs.
bool hasPlatformRole(dynamic node, String role) {
  const roles = {
    'button': ['ControlType.Button', 'AXButton', 'push button'],
    'checkbox': ['ControlType.CheckBox', 'AXCheckBox', 'check box'],
    'input': ['ControlType.Edit', 'AXTextField', 'entry'],
    'select': ['ControlType.ComboBox', 'AXPopUpButton', 'combo box'],
    'slider': ['ControlType.Slider', 'AXSlider', 'slider'],
    'table': ['ControlType.Table', 'AXTable', 'table'],
    'row': ['ControlType.DataItem', 'AXRow', 'table row'],
    'cell': ['ControlType.DataItem', 'AXCell', 'table cell'],
  };
  return node != null && roles[role]!.contains(node['role']);
}
