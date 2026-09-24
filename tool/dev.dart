import 'dart:async';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main() async {
  final session = await DevSession.start();
  Timer? debounce;
  var reload = Future<void>.value();
  final watchers = <StreamSubscription<FileSystemEvent>>[];
  for (final path in ['example', 'lib']) {
    watchers.add(
      Directory(path).watch(recursive: true).listen((event) {
        if (!event.path.endsWith('.dart')) return;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), () {
          reload = reload.then((_) async {
            try {
              final result = await session.reload();
              stdout.writeln('Reloaded: $result');
            } catch (error) {
              stderr.writeln(error);
            }
          });
        });
      }),
    );
  }
  stdout.writeln(
    'Watching example/ and lib/. Save Dart code to reload. Close the window to exit.',
  );
  try {
    exitCode = await session.process.exitCode;
  } finally {
    debounce?.cancel();
    for (final watcher in watchers) {
      await watcher.cancel();
    }
    await reload;
    await session.service.dispose();
    await removeSessionDirectory(session.directory);
  }
}
