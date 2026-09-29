import 'dart:convert';
import 'dart:io';

import 'commands.dart';
import 'toolchain.dart';

Future<String>? _tool;

Future<String> windowsTool() => _tool ??= _buildTool();

Future<String> _buildTool() async {
  if (!Platform.isWindows) {
    throw UnsupportedError('This check requires Windows');
  }
  await command('cargo', [
    'build',
    '--locked',
    '--release',
    '--manifest-path',
    'tool/windows/native/Cargo.toml',
  ], environment: toolchainEnvironment());
  return File('tool/windows/native/target/release/gpuidart-windows-tool.exe')
      .absolute
      .path;
}

Future<dynamic> windowsQuery(List<String> arguments) async {
  final result = await Process.run(
    await windowsTool(),
    arguments,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) throw StateError('${result.stderr}');
  return jsonDecode('${result.stdout}');
}

Future<void> watchlistStep(int pid, String step) async {
  const captures = {
    'capture': 'watchlist-edited.png',
    'capture-small': 'watchlist-small.png',
    'capture-footer': 'watchlist-footer.png',
  };
  await windowsQuery([
    'watchlist',
    '$pid',
    step,
    if (captures.containsKey(step)) 'reports/sdk/visual/${captures[step]}',
  ]);
}
