import 'dart:io';

import 'src/commands.dart';
import 'src/toolchain.dart';

Future<void> main(List<String> args) async {
  if (args.length > 1 ||
      (args.isNotEmpty && !args.single.startsWith('--output='))) {
    throw ArgumentError(
      'Usage: dart run tool/build_cli.dart [--output=EXECUTABLE]',
    );
  }
  final output = args.isEmpty
      ? 'build/bin/gpuidart${Platform.isWindows ? '.exe' : ''}'
      : args.single.substring('--output='.length);
  if (output.isEmpty) throw ArgumentError('--output requires a path');
  File(output).parent.createSync(recursive: true);
  stdout.writeln(
    await command(dartExecutable, [
      'compile',
      'exe',
      'bin/gpuidart.dart',
      '-o',
      output,
    ]),
  );
}
