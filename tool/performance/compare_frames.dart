import 'dart:convert';
import 'dart:io';

/// Prints per-frame draw cost and materialization counts from snapshot-gate
/// series: for each run directory's report.json, the draw histogram p50 of
/// the last sample and the native materialization count, grouped by run
/// name across repetitions (median of the runs). Usage:
/// compare_frames.dart SERIES_DIRECTORY [SERIES_DIRECTORY ...]
void main(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError('Usage: compare_frames.dart SERIES_DIRECTORY ...');
  }
  for (final series in args) {
    final byGroup = <String, List<(double, int)>>{};
    for (final entry in Directory(series).listSync()) {
      final report = File('${entry.path}/report.json');
      if (entry is! Directory || !report.existsSync()) continue;
      final json =
          jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
      final samples = json['samples'] as List;
      final last = samples.last as Map<String, dynamic>;
      final draw = (last['draw'] as Map<String, dynamic>)['p50_us'] as num;
      final materializations =
          (last['native'] as Map<String, dynamic>)['materializations'] as int;
      final name = entry.uri.pathSegments
          .lastWhere((segment) => segment.isNotEmpty)
          .replaceFirst(RegExp(r'-\d+$'), '');
      byGroup.putIfAbsent(name, () => []).add((
        draw.toDouble(),
        materializations,
      ));
    }
    print('== $series');
    for (final name in byGroup.keys.toList()..sort()) {
      final runs = byGroup[name]!;
      final draws = runs.map((r) => r.$1).toList()..sort();
      final counts = runs.map((r) => r.$2).toList()..sort();
      print(
        '${name.padRight(10)} draw p50 ${draws[draws.length ~/ 2].toStringAsFixed(0)} us, '
        'materializations ${counts[counts.length ~/ 2]} (${runs.length} runs)',
      );
    }
  }
}
