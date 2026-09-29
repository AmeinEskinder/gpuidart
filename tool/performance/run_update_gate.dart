import 'dart:io';

import '../../benchmarks/src/common.dart';
import '../../benchmarks/src/process.dart';
import '../src/toolchain.dart';

/// Each checkout supplies its own SDK and native library. Process environments
/// are rebuilt for each side so portable compiler paths cannot leak between them.
Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final baseline = Directory(o.string('baseline')).absolute.path,
      output = Directory(o.string('output')).absolute.path,
      targetDir = o.string('target-dir', ''),
      sides = o.string('sides', 'trunk,head').split(',');
  o.done();
  if (sides.isEmpty ||
      sides.any((s) => !['trunk', 'head'].contains(s)) ||
      sides.toSet().length != sides.length) {
    throw ArgumentError('Sides must be distinct trunk,head entries');
  }
  final candidates = {'trunk': baseline, 'head': repositoryRoot()};
  Directory(output).createSync(recursive: true);
  for (final entry in candidates.entries) {
    if (!sides.contains(entry.key)) continue;
    final name = entry.key, root = entry.value;
    if (Directory('$output/$name').existsSync()) {
      throw StateError('Retain the previous $name series in $output');
    }
    final env = toolchainEnvironment(root: root);
    if (targetDir.isNotEmpty) {
      env['CARGO_TARGET_DIR'] = Directory(targetDir).absolute.path;
    }
    final target = env['CARGO_TARGET_DIR'] ?? '$root/target';
    await execute(
      'cargo',
      [
        'build',
        '--locked',
        '--release',
        '-p',
        'gpuidart',
        '-p',
        'gpuidart-launcher',
      ],
      cwd: root,
      environment: env,
    );
    final native = '$output/$name-native';
    Directory(native).createSync(recursive: true);
    final library = Platform.isWindows
        ? 'gpuidart.dll'
        : Platform.isMacOS
        ? 'libgpuidart.dylib'
        : 'libgpuidart.so';
    for (final file in [
      library,
      'gpuidart-launcher${Platform.isWindows ? '.exe' : ''}',
    ]) {
      File('$target/release/$file').copySync('$native/$file');
    }
    final revision = await execute('git', ['rev-parse', 'HEAD'], cwd: root),
        status = await execute('git', ['status', '--porcelain'], cwd: root);
    File('$native/source.txt')
        .writeAsStringSync('${revision.stdout}${status.stdout}');
    await execute(
      dartExecutable,
      [
        'run',
        'tool/performance/run_snapshot_gate.dart',
        '$output/$name',
        native,
      ],
      cwd: root,
      environment: env,
    );
    await execute(
      dartExecutable,
      [
        'run',
        'tool/performance/summarize_snapshot_gate.dart',
        '$output/$name',
        '$output/$name-summary.json',
      ],
      cwd: root,
      environment: env,
    );
  }
  stdout.writeln('Gate series complete: $output');
});
