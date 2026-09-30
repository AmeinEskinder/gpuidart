import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/src/platform.dart';

import 'src/commands.dart';
import 'src/toolchain.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--headless')) {
    throw ArgumentError('Usage: dart run tool/check.dart [--headless]');
  }
  final headless = args.contains('--headless');
  Future<void> run(String executable, List<String> arguments) async {
    stdout.writeln('> $executable ${arguments.join(' ')}');
    final process = await startCommand(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final status = await process.exitCode;
    if (status != 0) exit(status);
  }

  /// Like [run], but returns the output so the gate can read the suite
  /// counts it just produced.
  Future<String> runCapturing(String executable, List<String> arguments) async {
    stdout.writeln('> $executable ${arguments.join(' ')}');
    final process = await startCommand(executable, arguments);
    final captured = StringBuffer();
    final streams = Future.wait([
      process.stdout.transform(utf8.decoder).forEach((chunk) {
        stdout.write(chunk);
        captured.write(chunk);
      }),
      process.stderr.transform(utf8.decoder).forEach((chunk) {
        stderr.write(chunk);
        captured.write(chunk);
      }),
    ]);
    final status = await process.exitCode;
    await streams;
    if (status != 0) exit(status);
    return captured.toString();
  }

  await run(dartExecutable, ['run', 'tool/accessibility/verify_vendor.dart']);
  await run(dartExecutable, [
    'run',
    'tool/source_inventory.dart',
    '--report=build/source-inventory.json',
  ]);
  await run('cargo', ['fmt', '--all', '--check']);
  for (final manifest in [
    'tool/native_probe/Cargo.toml',
    'benchmarks/driver/Cargo.toml',
    if (Platform.isWindows) 'tool/windows/native/Cargo.toml',
  ]) {
    await run('cargo', ['fmt', '--manifest-path', manifest, '--', '--check']);
    await run('cargo', ['test', '--locked', '--manifest-path', manifest]);
  }
  await run(dartExecutable, ['run', 'tool/build_cli.dart']);
  await run('build/bin/gpuidart${Platform.isWindows ? '.exe' : ''}', [
    'doctor',
  ]);
  await run('rustfmt', [
    '--edition',
    '2024',
    '--check',
    'test/fixtures/fault_host.rs',
  ]);
  final nativeOutput = await runCapturing('cargo', [
    'test',
    '--locked',
    '-p',
    'gpuidart',
  ]);
  final nativeCount = RegExp(r'test result: ok\. (\d+) passed')
      .firstMatch(nativeOutput)
      ?.group(1);
  await run('cargo', [
    'test',
    '--locked',
    '-p',
    'gpuidart',
    '--lib',
    '--features',
    'snapshot-experiment',
    'experiment',
  ]);
  await run('cargo', ['build', '--locked', '-p', 'gpuidart-launcher']);
  if (!headless) await run('cargo', ['build', '--locked', '-p', 'gpuidart']);
  await run(dartExecutable, [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'bin',
    'lib',
    'example',
    'test',
    'tool',
    'benchmarks',
  ]);
  await run(dartExecutable, ['analyze', '--fatal-infos']);
  await run(dartExecutable, ['test', 'benchmarks/analysis_test.dart']);
  Directory('.cache').createSync(recursive: true);
  await run('rustc', [
    '--edition=2024',
    '--crate-type',
    'cdylib',
    '-A',
    'private_interfaces',
    'test/fixtures/fault_host.rs',
    '-o',
    '.cache/${nativeLibraryName('fault_host')}',
  ]);
  final dartOutput = await runCapturing(dartExecutable, [
    'test',
    '--reporter=expanded',
    if (headless) ...['--exclude-tags', 'live-window'],
  ]);
  final dartCount = RegExp(r'\+(\d+): All tests passed')
      .firstMatch(dartOutput)
      ?.group(1);
  // The roadmap records the Windows full gate's counts; other platforms and
  // the headless gate run different subsets, so they check the prose only.
  await run(dartExecutable, [
    'run',
    'tool/docs_check.dart',
    if (Platform.isWindows && nativeCount != null) '--native=$nativeCount',
    if (Platform.isWindows && !headless && dartCount != null)
      '--dart=$dartCount',
  ]);
}
