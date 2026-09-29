import 'dart:io';

import 'src/commands.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('Usage: dart run tool/env.dart COMMAND [ARGUMENTS]');
    return;
  }
  final process = await startCommand(
    args.first,
    args.skip(1).toList(),
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}
