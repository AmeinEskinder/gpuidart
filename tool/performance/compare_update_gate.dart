import 'dart:convert';
import 'dart:io';

/// Prints a Markdown comparison of two snapshot-gate summaries, one per side.
/// Values are the medians across runs of each run's median; ratios are head
/// over trunk. Usage: compare_update_gate.dart TRUNK_SUMMARY HEAD_SUMMARY
Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: compare_update_gate.dart TRUNK_SUMMARY.json HEAD_SUMMARY.json',
    );
  }
  final trunk = await _groups(args[0]);
  final head = await _groups(args[1]);
  const metrics = [
    ('bytes', 'Bytes'),
    ('dart.build.us', 'Dart build, us'),
    ('dart.describe.us', 'Describe, us'),
    ('dart.diff.us', 'Diff, us'),
    ('dart.encode.us', 'Encode/copy, us'),
    ('native.parse.us', 'Native decode/validate, us'),
    ('native.dispatch.us', 'Native dispatch, us'),
    ('publish_to_ack.us', 'Publish to ack, us'),
    ('request_to_first_content_paint.us', 'Request to first content paint, us'),
  ];
  final keys = {...trunk.keys, ...head.keys}.toList()
    ..sort((a, b) {
      final left = _order(a);
      final right = _order(b);
      for (var i = 0; i < 3; i++) {
        final by = left[i].compareTo(right[i]);
        if (by != 0) return by;
      }
      return 0;
    });
  final out = StringBuffer();
  out.writeln(
    '| Mode, fields, operation | Metric | Trunk | Head | Head / trunk |',
  );
  out.writeln('| --- | --- | ---: | ---: | ---: |');
  for (final key in keys) {
    for (final (metric, label) in metrics) {
      final before = _median(trunk[key], metric);
      final after = _median(head[key], metric);
      if (before == null && after == null) continue;
      final ratio = before != null && after != null && before > 0
          ? (after / before).toStringAsFixed(2)
          : '';
      out.writeln(
        '| $key | $label | ${_format(before)} | ${_format(after)} | $ratio |',
      );
    }
  }
  stdout.write(out);
}

Future<Map<String, Map<String, dynamic>>> _groups(String path) async {
  final summary = jsonDecode(await File(path).readAsString()) as Map;
  if ((summary['failed_runs'] as List).isNotEmpty) {
    throw StateError('$path records failed runs; do not compare');
  }
  return (summary['groups'] as Map).map(
    (key, value) =>
        MapEntry(key as String, (value as Map).cast<String, dynamic>()),
  );
}

double? _median(Map<String, dynamic>? group, String metric) {
  final entry = group?['$metric.run_median'] as Map?;
  return (entry?['median'] as num?)?.toDouble();
}

String _format(double? value) => value == null
    ? ''
    : value >= 100
    ? value.round().toString()
    : value.toStringAsFixed(2);

List<Comparable> _order(String key) {
  final parts = key.split('-');
  const operations = ['unchanged', 'property', 'reorder', 'insert', 'remove'];
  return [
    parts[0],
    int.tryParse(parts[1]) ?? 0,
    operations.indexOf(parts.sublist(2).join('-')),
  ];
}
