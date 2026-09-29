import 'dart:io';

import 'src/common.dart';
import 'src/process.dart';
import '../tool/src/toolchain.dart';
import 'package.dart' show packageBenchmarks;

const kitRevision = '0c830f4d257e69fdd17200650533ab4ca9a40cc0';
Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args, flags: {'no-flutter'});
  final noFlutter = o.flag('no-flutter');
  o.done();
  if (!Platform.isWindows) {
    throw UnsupportedError('The comparison fixtures currently target Windows.');
  }
  final root = repositoryRoot();
  if (!File('$root/.cache/gpui-kit/Cargo.toml').existsSync()) {
    await execute('git', [
      'clone',
      'https://github.com/longbridge/gpui-kit',
      '.cache/gpui-kit',
    ]);
    await execute('git', [
      '-C',
      '.cache/gpui-kit',
      'checkout',
      '--detach',
      kitRevision,
    ]);
  }
  final revision = await execute('git', [
    '-C',
    '.cache/gpui-kit',
    'rev-parse',
    'HEAD',
  ]);
  if ('${revision.stdout}'.trim() != kitRevision) {
    throw StateError('Benchmark requires the pinned GPUI Kit checkout');
  }
  final edits = await execute('git', [
    '-C',
    '.cache/gpui-kit',
    'status',
    '--porcelain',
    '--untracked-files=no',
  ]);
  if ('${edits.stdout}'.trim().isNotEmpty) {
    throw StateError('GPUI Kit reference source has local edits');
  }
  await execute('cargo', [
    'build',
    '--locked',
    '--release',
    '-p',
    'gpuidart',
    '-p',
    'gpui-native-comparison',
  ]);
  await execute('cargo', [
    'build',
    '--locked',
    '--release',
    '--manifest-path',
    '.cache/gpui-kit/Cargo.toml',
    '--target-dir',
    'target',
    '-p',
    'gpui-component-shell',
  ]);
  Directory('$root/build').createSync(recursive: true);
  await execute(dartExecutable, [
    'compile',
    'exe',
    'benchmarks/dart/main.dart',
    '-o',
    'build/gpui-dart-comparison.exe',
  ]);
  for (final command in [
    ['install', '--frozen-lockfile'],
    ['run', 'check'],
    ['run', 'build'],
  ]) {
    await execute('bun', command, cwd: '$root/benchmarks/solid');
  }
  if (!noFlutter) {
    final env = toolchainEnvironment(root: root)
      ..removeWhere(
        (key, value) => [
          'CC',
          'CXX',
          'AR',
          'INCLUDE',
          'LIB',
          'CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_LINKER',
        ].contains(key.toUpperCase()),
      );
    await execute(
      'flutter',
      ['pub', 'get', '--enforce-lockfile'],
      cwd: '$root/benchmarks/flutter',
      environment: env,
    );
    await execute(
      'flutter',
      ['build', 'windows', '--release'],
      cwd: '$root/benchmarks/flutter',
      environment: env,
    );
  }
  await packageBenchmarks(noFlutter: noFlutter);
});
