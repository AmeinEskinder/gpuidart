import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

Future<void> main(List<String> args) async {
  try {
    final host = await GpuiHost.open(
      const UiText('root', 'Failure probe'),
      requestTimeout: const Duration(milliseconds: 250),
    );
    await host.close();
    throw StateError('Broken companion unexpectedly opened');
  } catch (error) {
    final expected = args.single == 'hung'
        ? '$error'.contains('No native acknowledgement for startup')
        : '$error'.contains('did not connect') || '$error'.contains('code 7');
    if (!expected) rethrow;
    stdout.writeln('EXPECTED: $error');
  }
}
