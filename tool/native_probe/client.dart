import 'dart:io';

import '../src/commands.dart';

Future<String>? _build;

/// Build once per driver process. Cargo checks freshness against the pinned
/// helper manifest, so an old executable cannot silently supply probe evidence.
Future<String> nativeProbe() => _build ??= _buildProbe();

Future<String> _buildProbe() async {
  await command('cargo', [
    'build',
    '--locked',
    '--manifest-path',
    'tool/native_probe/Cargo.toml',
    '--target-dir',
    'build/native-probe',
  ]);
  final binary = File(
    'build/native-probe/debug/gpuidart-native-probe${Platform.isWindows ? '.exe' : ''}',
  );
  if (!binary.existsSync()) {
    throw StateError('Cargo did not produce ${binary.path}');
  }
  return binary.absolute.path;
}
