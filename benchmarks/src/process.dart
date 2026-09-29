import 'dart:io';

import '../../tool/src/toolchain.dart';
import 'common.dart';

Future<ProcessResult> execute(
  String name,
  List<String> args, {
  String? cwd,
  Map<String, String>? environment,
  bool check = true,
}) async {
  final env = environment ?? toolchainEnvironment(root: repositoryRoot());
  final exe = toolExecutable(name, env);
  stdout.writeln('> $name ${args.join(' ')}');
  final result = await Process.run(
    exe,
    args,
    workingDirectory: cwd ?? repositoryRoot(),
    environment: env,
    includeParentEnvironment: false,
    runInShell:
        Platform.isWindows && (exe.endsWith('.bat') || exe.endsWith('.cmd')),
  );
  if (check && result.exitCode != 0) {
    throw ProcessException(
      exe,
      args,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

Future<String> driverExecutable() async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Window benchmarks require Windows; analysis and reporting run on every platform.',
    );
  }
  final root = repositoryRoot();
  await execute('cargo', [
    'build',
    '--locked',
    '--release',
    '--manifest-path',
    '$root/benchmarks/driver/Cargo.toml',
    '--target-dir',
    '$root/build/benchmark-driver',
  ]);
  return '$root/build/benchmark-driver/release/gpuidart-benchmark-driver.exe';
}

String fixtureExecutable(
  String implementation, {
  bool packaged = false,
  bool trace = false,
}) {
  final root = repositoryRoot();
  final source = switch (implementation) {
    'rust' =>
      trace
          ? 'build/comparison-trace/gpui-native-comparison.exe'
          : 'target/release/gpui-native-comparison.exe',
    'dart' => 'build/gpui-dart-comparison.exe',
    'solid' => 'benchmarks/solid/dist/gpui-solid-comparison.exe',
    'shell' => 'target/release/gpui-component-shell.exe',
    'flutter' => 'benchmarks/flutter/build/windows/x64/runner/Release/gpui_flutter_comparison.exe',
    _ => throw ArgumentError('Unknown implementation $implementation'),
  };
  return packaged
      ? '$root/build/comparison/$implementation/${source.split('/').last}'
      : '$root/$source';
}

void copyTree(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final entry in source.listSync(followLinks: false)) {
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is File) entry.copySync('${destination.path}/$name');
    if (entry is Directory) {
      copyTree(entry, Directory('${destination.path}/$name'));
    }
  }
}
