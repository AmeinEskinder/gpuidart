import 'dart:async';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == '--help') {
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
  var closing = false;
  var reload = Future<void>.value();
  final watchers = <StreamSubscription<FileSystemEvent>>[];
  final interrupt = ProcessSignal.sigint.watch().listen((_) {
    closing = true;
    unawaited(session.close());
  });
  try {
    for (final path in {
      File(entry).absolute.parent.path,
      Directory('lib').absolute.path,
    }) {
      watchers.add(
        Directory(path).watch(recursive: true).listen((event) {
          if (closing || !event.path.endsWith('.dart')) return;
          debounce?.cancel();
          debounce = Timer(const Duration(milliseconds: 250), () {
            reload = reload.then((_) async {
              if (closing) return;
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
    exitCode = await session.process.exitCode;
  } finally {
    closing = true;
    debounce?.cancel();
    await interrupt.cancel();
    for (final watcher in watchers) {
      await watcher.cancel();
    }
    await reload;
    await session.close();
  }
}
