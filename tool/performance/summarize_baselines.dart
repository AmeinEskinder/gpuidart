import 'dart:convert';
import 'dart:io';

/// Reduces raw captures without pooling repetitions or conflating memory metrics.
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: summarize_baselines.dart CAPTURE_DIRECTORY NEW_OUTPUT_JSON',
    );
  }
  final directory = Directory(args[0]);
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Retain earlier summary');
  final summary = jsonDecode(
    await File('${directory.path}/summary.json').readAsString(),
  ) as Map;
  final groups = <String, Map<String, List<double>>>{};
  final failures = <Object?>[];
  for (final run in (summary['runs'] as List).cast<Map>()) {
    final name = run['name'] as String;
    if (run['passed'] != true) {
      failures.add(run);
      continue;
    }
    final app = jsonDecode(
      await File('${directory.path}/$name.application.json').readAsString(),
    ) as Map;
    final group = groups.putIfAbsent(
      name.replaceFirst(RegExp(r'-\d+$'), ''),
      () => {},
    );
    void add(String metric, num value) =>
        group.putIfAbsent(metric, () => []).add(value.toDouble());
    final frequency = app['frequency'] as num;
    for (final entry in (run['from_driver_launch_us'] as Map).entries) {
      add('startup_us.${entry.key}', entry.value as num);
    }
    if (run['first_content_paint_from_launch_us'] case final num value) {
      add('startup_us.first_content_paint', value);
    }
    if (app['trace'] case final Map trace) {
      for (final record in (trace['records'] as List).cast<Map>().where(
        (r) => r['operation'] == 'initial',
      )) {
        final duration = (record['end'] as int) - (record['start'] as int);
        if (duration > 0) {
          add('stage_us.${record['name']}', duration * 1000000 / frequency);
        }
        if (record['bytes'] case final num value) {
          add('bytes.${record['name']}', value);
        }
      }
    }
    final settled = (app['memory'] as Map)['settled_samples'] as List;
    final local = <String, List<double>>{};
    void sampleMetric(String key, num value) =>
        local.putIfAbsent(key, () => []).add(value.toDouble());
    for (final sample in settled.cast<Map>()) {
      if (sample['roles'] case final Map roles) {
        for (final entry in roles.entries) {
          final process = (sample['by_pid'] as Map)['${entry.value}'] as Map;
          for (final section in [
            'memory_bytes',
            'memory_peak_bytes',
            'rust_allocator',
          ]) {
            if (process[section] case final Map counters) {
              for (final counter in counters.entries) {
                if (counter.value case final num value) {
                  sampleMetric('${entry.key}.$section.${counter.key}', value);
                }
              }
            }
          }
        }
      } else {
        final process = sample['application'] as Map;
        sampleMetric(
          'application.process_info.rss_bytes',
          process['rss_bytes'] as num,
        );
        sampleMetric(
          'application.process_info.peak_rss_bytes',
          process['peak_rss_bytes'] as num,
        );
      }
    }
    for (final entry in local.entries) {
      add('settled.${entry.key}', median(entry.value));
    }
    if (app['inspect_round_trip_ticks'] case final List values) {
      final times = values
          .cast<num>()
          .map((n) => n * 1000000 / frequency)
          .toList();
      add('inspect_round_trip_us.run_median', median(times));
      add('inspect_round_trip_us.run_p95', quantile(times, .95));
    }
  }
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'capture_directory': directory.path,
      'failed_runs': failures,
      'groups': {
        for (final group in groups.entries) group.key: {
            for (final metric in group.value.entries) metric.key: {'samples': metric.value, 'median': median(metric.value), 'min': (metric.value.toList()..sort()).first, 'max': (metric.value.toList()..sort()).last},
          },
      },
      'scope': 'Each settled-memory value is the median of three observations in one process; group medians summarize fresh-process repetitions. Round-trip run summaries are not pooled. OS peaks are lifetime peaks. Application/UI roles can name the same PID; never sum these role fields as unique memory. Initial spans overlap.',
    })}\n',
  );
  if (failures.isNotEmpty) exitCode = 1;
}

double median(List<double> source) {
  final values = source.toList()..sort();
  final mid = values.length ~/ 2;
  return values.length.isOdd
      ? values[mid]
      : (values[mid - 1] + values[mid]) / 2;
}

double quantile(List<double> source, double fraction) =>
    (source.toList()..sort())[(source.length * fraction).ceil() - 1];
