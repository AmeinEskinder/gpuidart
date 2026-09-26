import 'dart:io';

import 'package:gpuidart/development.dart';

import 'app.dart';

Future<void> main() async {
  final app = await SettingsApplication.open();
  registerGpuiReload(app.host, describe: app.describe);
  try {
    await app.host.done;
    if (app.failure != null) {
      stderr.writeln(app.failure);
      exitCode = 1;
    }
  } finally {
    await app.close();
  }
}
