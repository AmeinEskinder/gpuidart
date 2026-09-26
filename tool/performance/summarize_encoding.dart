import 'dart:convert';
import 'dart:io';

import 'summarize_baselines.dart' show median, quantile;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: summarize_encoding.dart CAPTURE_DIRECTORY NEW_OUTPUT_JSON',
    );
  }
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Retain earlier summary');
  final series =
      jsonDecode(await File('${args[0]}/summary.json').readAsString()) as Map;
  final groups = <String, Map<String, List<double>>>{};
  final failures = <Object?>[];
  for (final run in (series['runs'] as List).cast<Map>()) {
    if (run['passed'] != true) {
      failures.add(run);
      continue;
    }
    final capture = jsonDecode(
      await File('${args[0]}/${run['name']}.json').readAsString(),
    ) as Map;
    final group = groups.putIfAbsent(
      '${run['mode']}-${capture['fixture']}-${capture['encoder']}',
      () => {},
    );
    void add(String key, num value) =>
        group.putIfAbsent(key, () => []).add(value.toDouble());
    for (final key in ['first_encode_us', 'bytes']) {
      add(key, capture[key] as num);
    }
    final times = (capture['subsequent_encode_us'] as List)
        .cast<num>()
        .map((n) => n.toDouble())
        .toList();
    add('subsequent_median_us', median(times));
    add('subsequent_p95_us', quantile(times, .95));
    for (final stage in ['before', 'after']) {
      for (final entry in (capture[stage] as Map).entries) {
        add('$stage.${entry.key}', entry.value as num);
      }
    }
  }
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'failures': failures,
      'groups': {
        for (final group in groups.entries) group.key: {
            for (final metric in group.value.entries) metric.key: {'samples': metric.value, 'median': median(metric.value)},
          },
      },
      'scope': 'Encoding-only, first call separate from 25 subsequent calls. Run medians/percentiles then medians across fresh-process repetitions. RSS and process peak include fixture/runtime and natural GC; no presentation, FFI or native rendering measured.',
    })}\n',
  );
  if (failures.isNotEmpty) exitCode = 1;
}
