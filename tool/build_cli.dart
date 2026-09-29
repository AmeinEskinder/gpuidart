import 'dart:io';

import 'src/commands.dart';
import 'src/toolchain.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    throw ArgumentError('Usage: dart run tool/build_cli.dart');
  }
  Directory('build/bin').createSync(recursive: true);
  stdout.writeln(
    await command(dartExecutable, [
      'compile',
      'exe',
      'bin/gpuidart.dart',
      '-o',
      'build/bin/gpuidart${Platform.isWindows ? '.exe' : ''}',
    ]),
  );
}
