import 'dart:io';

import 'toolchain.dart';

Future<Process> startCommand(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  final childEnvironment = toolchainEnvironment(environment: environment);
  return Process.start(
    toolExecutable(executable, childEnvironment),
    args,
    environment: childEnvironment,
    includeParentEnvironment: false,
    workingDirectory: workingDirectory,
    mode: mode,
  );
}

Future<String> command(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  stdout.writeln('> $executable ${args.join(' ')}');
  final childEnvironment = toolchainEnvironment(environment: environment);
  final result = await Process.run(
    toolExecutable(executable, childEnvironment),
    args,
    environment: childEnvironment,
    includeParentEnvironment: false,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode != 0) {
    throw StateError(
      '$executable failed (${result.exitCode}): ${result.stdout}\n${result.stderr}',
    );
  }
  return '${result.stdout}'.trim();
}

Future<void> buildNative({required bool release}) async {
  final arguments = [
    'build',
    '--locked',
    '-p',
    'gpuidart',
    '-p',
    'gpuidart-launcher',
    if (release) '--release',
  ];
  stdout.writeln('> cargo ${arguments.join(' ')}');
  final process = await startCommand(
    'cargo',
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final status = await process.exitCode;
  if (status != 0) throw StateError('Native build failed ($status)');
  stdout.writeln(
    await command(dartExecutable, ['pub', 'get', '--enforce-lockfile']),
  );
}
