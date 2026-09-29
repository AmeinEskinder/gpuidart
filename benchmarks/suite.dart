import 'dart:io';

import 'src/common.dart';
import 'run.dart';

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args, flags: {'background-smoke', 'capture-present'});
  final id = o.string(
    'run-id',
    DateTime.now().toIso8601String().replaceAll(RegExp(r'[^0-9]'), ''),
  );
  final repeats = o.integer('repetitions', 3, 1, 100),
      seconds = o.integer('seconds', 10, 2, 120);
  final selected = o.selection('rust,shell,solid,dart'),
      background = o.flag('background-smoke'),
      capture = o.flag('capture-present');
  o.done();
  for (var repeat = 0; repeat < repeats; repeat++) {
    for (var index = 0; index < selected.length; index++) {
      final implementation = selected[(index + repeat) % selected.length];
      for (final workload in workloads) {
        final code = await runBenchmark([
          '--implementation',
          implementation,
          '--workload',
          workload,
          '--run-id',
          '$id-$repeat',
          '--seconds',
          '$seconds',
          if (background) '--background-smoke',
          if (capture) '--capture-present',
        ]);
        if (code == 2) {
          stderr.writeln(
            'Retained correctness failure at $implementation $workload repetition $repeat',
          );
        }
      }
    }
  }
});
