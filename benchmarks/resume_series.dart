import 'dart:io';

import 'src/common.dart';
import 'run.dart';

List<Directory> seriesDirectories(String reports, String prefix, int repeat) {
  final root = Directory(reports);
  if (!root.existsSync()) return [];
  final pattern = RegExp(
    '^${RegExp.escape('$prefix-$repeat')}(?:-retry[0-9]+)?\$',
  );
  return root
      .listSync()
      .whereType<Directory>()
      .where(
        (d) => pattern.hasMatch(
          d.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ),
      )
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final prefix = o.string('run-prefix'),
      repeats = o.integer('repetitions', 3, 1, 100),
      seconds = o.integer('seconds', 10, 2, 120),
      selected = o.selection(),
      limit = o.integer('attempts-per-slot', 3, 1, 10);
  o.done();
  final reports = '${repositoryRoot()}/reports/comparison',
      incomplete = <String>[];
  for (var repeat = 0; repeat < repeats; repeat++) {
    for (var index = 0; index < selected.length; index++) {
      final implementation = selected[(index + repeat) % selected.length];
      for (final workload in workloads) {
        final slot = '$implementation-$workload';
        if (seriesDirectories(
          reports,
          prefix,
          repeat,
        ).any((d) => File('${d.path}/$slot/run.json').existsSync())) {
          continue;
        }
        var finished = false;
        for (var attempt = 0; attempt < limit; attempt++) {
          var suffix = 0;
          var id = '$prefix-$repeat';
          while (Directory('$reports/$id/$slot').existsSync()) {
            id = '$prefix-$repeat-retry${++suffix}';
          }
          stdout.writeln('Running $slot repetition $repeat as $id');
          try {
            await runBenchmark([
              '--implementation',
              implementation,
              '--workload',
              workload,
              '--run-id',
              id,
              '--seconds',
              '$seconds',
            ]);
            finished = true;
            break;
          } catch (error) {
            stderr.writeln(error);
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
        if (!finished) incomplete.add('$slot repetition $repeat');
      }
    }
  }
  if (incomplete.isNotEmpty) {
    stderr.writeln(
      'Incomplete after $limit attempts each: ${incomplete.join('; ')}',
    );
    exitCode = 3;
  } else {
    stdout.writeln(
      'Series $prefix complete: $repeats repetitions of ${selected.join(', ')}.',
    );
  }
});
