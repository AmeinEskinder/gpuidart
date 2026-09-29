import 'dart:io';

import 'client.dart';

Future<void> main() async => stdout.writeln(await nativeProbe());
