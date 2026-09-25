import 'dart:async';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln(
      'dart run tool/dev.dart [entry.dart] [application arguments]',
    );
    stdout.writeln(
      'Default: example/watchlist/main.dart. Run from the project root.',
    );
    return;
  }
  final entry = args.isEmpty ? 'example/watchlist/main.dart' : args.first;
  if (!File(entry).existsSync()) {
    throw ArgumentError('Entry point not found: $entry');
  }
  final session = await DevSession.start(
    entry: entry,
    arguments: args.skip(1).toList(),
  );
  Timer? debounce;
  var reload = Future<void>.value();
  final watchers = <StreamSubscription<FileSystemEvent>>[];
  for (final path in {
    File(entry).absolute.parent.path,
    Directory('lib').absolute.path,
  }) {
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
    'Watching ${File(entry).parent.path}/ and lib/. Save Dart code to reload. Close the window to exit.',
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
