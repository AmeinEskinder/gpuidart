import 'dart:io';

import 'src/common.dart';
import 'src/process.dart';
import 'run.dart' show scrollOffset;

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final implementation = o.string('implementation', 'flutter'),
      deltas = o.string('deltas', '-120').split(',').map(int.parse).toList(),
      events = o.integer('events', 1, 1, 100000),
      interval = o.integer('interval-ms', 50, 0, 60000);
  o.done();
  if (implementation == 'shell') {
    throw ArgumentError(
      'Shell reports a visible range rather than a displacement; calibrate it from a scroll run',
    );
  }
  final driver = await driverExecutable(),
      root = repositoryRoot(),
      folder =
          '${repositoryRoot()}/reports/comparison/calibration-$implementation';
  Directory(folder).createSync(recursive: true);
  final results = <Json>[];
  for (final delta in deltas) {
    final output = '$folder/delta-$delta.json';
    if (File(output).existsSync()) File(output).deleteSync();
    final config = '$folder/calibration-config.json';
    writeJson(config, {
      'executable': fixtureExecutable(implementation),
      'arguments': [output],
      'folder': folder,
      'environment': {'GPUIDART_LIBRARY': '$root/target/release/gpuidart.dll'},
      'workload': 'scroll',
      'seconds': 2,
      'background': false,
      'no_pointer_warmup': false,
      'shell': false,
      'wheel_delta': delta,
      'calibration': {'events': events, 'interval_ms': interval},
    });
    await execute(driver, ['--config', config]);
    File(config).deleteSync();
    final scroll = number(
      scrollOffset(readJson(output) as Json, implementation),
    );
    results.add({
      'implementation': implementation,
      'delta': delta,
      'events': events,
      'interval_ms': interval,
      'scroll_y': scroll,
      'per_event': scroll / events,
    });
    stdout.writeln(
      '$implementation delta $delta x $events -> scroll_y $scroll (${scroll / events} per event)',
    );
  }
  writeJson(
    '$folder/calibration.json',
    results.length == 1 ? results.single : results,
  );
});
