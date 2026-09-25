import 'dart:io';

import 'package:gpuidart/src/platform.dart';

Future<void> main(List<String> args) async {
  if (args.any((arg) => arg != '--headless')) {
    throw ArgumentError('Usage: dart run tool/check.dart [--headless]');
  }
  final headless = args.contains('--headless');
  Future<void> run(String executable, List<String> arguments) async {
    stdout.writeln('> $executable ${arguments.join(' ')}');
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final status = await process.exitCode;
    if (status != 0) exit(status);
  }

  await run('cargo', ['fmt', '--all', '--check']);
  await run('rustfmt', [
    '--edition',
    '2024',
    '--check',
    'test/fixtures/fault_host.rs',
  ]);
  await run('cargo', ['test', '--locked', '-p', 'gpuidart']);
  await run('cargo', ['build', '--locked', '-p', 'gpuidart-launcher']);
  if (!headless) await run('cargo', ['build', '--locked', '-p', 'gpuidart']);
  await run(Platform.resolvedExecutable, [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'lib',
    'test',
  ]);
  await run(Platform.resolvedExecutable, ['analyze', '--fatal-infos']);
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
  await run(Platform.resolvedExecutable, [
    'test',
    if (headless) ...['--exclude-tags', 'live-window'],
  ]);
}
