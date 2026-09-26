import 'dart:convert';
import 'dart:io';

import 'summarize_baselines.dart' show median, quantile;

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: summarize_snapshot_gate.dart CAPTURE_DIRECTORY NEW_OUTPUT_JSON',
    );
  }
  final directory = Directory(args[0]);
  final output = File(args[1]);
  if (output.existsSync()) throw StateError('Retain earlier summary');
  final series = jsonDecode(
    await File('${directory.path}/summary.json').readAsString(),
  ) as Map;
  final groups = <String, Map<String, List<num>>>{};
  final failures = <Object?>[];
  for (final run in (series['runs'] as List).cast<Map>()) {
    if (run['passed'] != true) {
      failures.add(run);
      continue;
    }
    final path = '${directory.path}/${run['name']}';
    final report =
        jsonDecode(await File('$path/report.json').readAsString()) as Map;
    final trace =
        jsonDecode(await File('$path/trace.json').readAsString()) as Map;
    final frequency = (trace['metadata'] as Map)['frequency'] as num;
    final records = (trace['records'] as List).cast<Map>();
    for (final operation in [
      'unchanged',
      'property',
      'reorder',
      'insert',
      'remove',
    ]) {
      final local = <String, List<double>>{};
      void add(String key, num value) =>
          local.putIfAbsent(key, () => []).add(value.toDouble());
      for (final sample in (report['samples'] as List).cast<Map>().where(
        (s) => s['operation'] == operation,
      )) {
        final revision = sample['revision'];
        final stages = records
            .where(
              (r) => r['operation'] == 'snapshot' && r['request'] == revision,
            )
            .toList();
        Map stage(String name) => stages.singleWhere((r) => r['name'] == name);
        add('bytes', sample['bytes'] as num);
        for (final name in [
          'dart.build',
          'dart.describe',
          'dart.encode',
          'dart.json',
          'dart.utf8',
          'dart.ffi_copy',
          'native.parse',
          'native.dispatch',
        ]) {
          final r = stage(name);
          add(
            '$name.us',
            ((r['end'] as num) - (r['start'] as num)) * 1000000 / frequency,
          );
        }
        add(
          'publish_to_ack.us',
          ((stage('dart.ack')['start'] as num) -
                  (stage('dart.request')['start'] as num)) *
              1000000 /
              frequency,
        );
        final paints =
            stages.where((r) => r['name'] == 'native.content_paint').toList()
              ..sort(
                (a, b) => (a['start'] as int).compareTo(b['start'] as int),
              );
        if (paints.isEmpty) {
          throw StateError('No CPU content paint for $path revision $revision');
        }
        add(
          'first_content_paint.us',
          ((paints.first['end'] as num) - (paints.first['start'] as num)) *
              1000000 /
              frequency,
        );
        add(
          'request_to_first_content_paint.us',
          ((paints.first['end'] as num) -
                  (stage('dart.request')['start'] as num)) *
              1000000 /
              frequency,
        );
      }
      final group = groups.putIfAbsent(
        '${report['mode']}-${report['fields']}-$operation',
        () => {},
      );
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
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'failed_runs': failures,
      'groups': {
        for (final group in groups.entries) group.key: {
            for (final metric in group.value.entries) metric.key: {'samples': metric.value, 'median': median(metric.value.map((n) => n.toDouble()).toList())},
          },
      },
      'scope': 'Per-operation summaries within each run, then medians across three runs. Eight samples per operation make run p95 the maximum. Native parse includes validation. First CPU content paint is matched by snapshot revision, not presentation. Whole-window draw histograms remain in raw reports and mix operations; do not attribute their percentiles to one operation.',
    })}\n',
  );
  if (failures.isNotEmpty) exitCode = 1;
}
