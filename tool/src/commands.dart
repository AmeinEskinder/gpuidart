import 'dart:io';

Future<String> command(
  String executable,
  List<String> args, {
  Map<String, String>? environment,
  String? workingDirectory,
}) async {
  stdout.writeln('> $executable ${args.join(' ')}');
  final result = await Process.run(
    executable,
    args,
    environment: environment,
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
  if (Platform.isWindows) {
    await command('powershell.exe', [
      '-NoProfile',
      '-File',
      'tool/build.ps1',
      if (release) '-Release',
    ]);
  } else {
    await command(
      'cargo',
      [
        'build',
        '--locked',
        '-p',
        'gpuidart',
        '-p',
        'gpuidart-launcher',
        if (release) '--release',
      ],
      environment: {if (Platform.isMacOS) 'MACOSX_DEPLOYMENT_TARGET': '15.0'},
    );
    await command(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--enforce-lockfile',
    ]);
  }
}
