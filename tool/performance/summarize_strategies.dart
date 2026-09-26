import 'dart:convert';
import 'dart:io';

import 'summarize_baselines.dart' show median, quantile;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: summarize_strategies.dart CAPTURE_DIRECTORY NEW_OUTPUT_JSON',
    );
  }
  final directory = Directory(args[0]);
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Retain earlier summary');
  final series = jsonDecode(
    await File('${directory.path}/summary.json').readAsString(),
  ) as Map;
  final groups = <String, Map<String, List<double>>>{};
  final memories = <String, Map<String, List<double>>>{};
  final failures = <Object?>[];
  var updates = 0, checks = 0;
  void flatten(Map values, String prefix, Map<String, List<double>> into) {
    for (final entry in values.entries) {
      final key = '$prefix${entry.key}';
      if (entry.value is num) {
        into.putIfAbsent(key, () => []).add((entry.value as num).toDouble());
      }
      if (entry.value is Map) flatten(entry.value as Map, '$key.', into);
    }
  }

  for (final run in (series['runs'] as List).cast<Map>()) {
    if (run['passed'] != true) {
      failures.add(run);
      continue;
    }
    final report = jsonDecode(
      await File('${directory.path}/${run['name']}/report.json').readAsString(),
    ) as Map;
    final identity =
        '${report['mode']}-${report['fields']}-${report['strategy']}';
    final memory = memories.putIfAbsent(identity, () => {});
    for (final stage in ['before', 'after_workload']) {
      final runtime = report[stage]['runtime'] as Map;
      for (final metric in [
        'memory_bytes',
        'memory_peak_bytes',
        'rust_allocator',
      ]) {
        if (runtime[metric] case final Map values) {
          flatten(values, 'native.$stage.$metric.', memory);
        }
      }
    }
    for (final stage in ['before', 'after']) {
      final values = Map.of(report['dart_memory_$stage'] as Map)..remove('pid');
      flatten(values, 'dart.$stage.', memory);
    }
    checks += (report['correctness'] as List).length;
    for (final operation in [
      'unchanged',
      'property',
      'reorder',
      'insert',
      'remove',
    ]) {
      final local = <String, List<double>>{};
      for (final sample in (report['samples'] as List).cast<Map>().where(
        (s) => s['operation'] == operation,
      )) {
        updates++;
        for (final key in [
          'build_us',
          'describe_us',
          'diff_us',
          'diff_nodes_visited',
          'native_decode_us',
        ]) {
          flatten({key: sample[key]}, '', local);
        }
        for (final key in ['transport', 'native_stages', 'frame']) {
          final values = Map.of(sample[key] as Map)
            ..remove('serial')
            ..remove('revision');
          flatten(values, '$key.', local);
        }
        // This is summed per update before summarizing, never added percentiles.
        flatten(
          {
            'dart_prepare_us':
                (sample['build_us'] as num) +
                (sample['describe_us'] as num) +
                (sample['diff_us'] as num) +
                (sample['transport']['encode_us'] as num),
          },
          '',
          local,
        );
        final stages = sample['native_stages'] as Map;
        flatten(
          {
            'native_prepare_us':
                (sample['native_decode_us'] as num) +
                (stages['staging_us'] as num) +
                (stages['validation_us'] as num) +
                (stages['application_us'] as num),
          },
          '',
          local,
        );
      }
      final group = groups.putIfAbsent('$identity-$operation', () => {});
      for (final metric in local.entries) {
        group
            .putIfAbsent('${metric.key}.run_median', () => [])
            .add(median(metric.value));
        group
            .putIfAbsent('${metric.key}.run_p95', () => [])
            .add(quantile(metric.value, .95));
      }
    }
  }
  Map summarize(Map<String, Map<String, List<double>>> input) => {
    for (final group in input.entries)
      group.key: {
        for (final metric in group.value.entries)
          metric.key: {'samples': metric.value, 'median': median(metric.value)},
      },
  };
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'failed_runs': failures, 'updates': updates, 'correctness_checks': checks, 'groups': summarize(groups), 'memory': summarize(memories), 'scope': 'Run medians then medians across repetitions; eight updates per operation, run p95 is the maximum. Framed process transport, not production FFI. Request/reply includes serializing full diagnostic replies and waiting for a CPU paint. Layout gap includes surrounding GPUI work, not isolated layout solver time. No presentation measurement. Allocation profile builds must be reported separately; native allocator excludes Dart/external/GPU allocations. Driver memory includes collected evidence. Subviews reject cross-owner retained-control moves.'})}\n',
  );
  if (failures.isNotEmpty) exitCode = 1;
}
