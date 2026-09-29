import 'dart:io';

import 'src/common.dart';
import 'analyze.dart';
import 'resume_series.dart' show seriesDirectories;

Json summarize(
  String reports,
  String prefix,
  int repetitions,
  List<String> selected,
) {
  final observations = <Json>[];
  for (var repeat = 0; repeat < repetitions; repeat++) {
    for (final dir in seriesDirectories(reports, prefix, repeat)) {
      for (final item in analyze(dir.path)) {
        if (!selected.contains(item['implementation'])) {
          throw StateError(
            'Unexpected implementation in series: ${item['implementation']}',
          );
        }
        observations.add(item);
      }
    }
  }
  final groups = <Json>[];
  for (final workload in workloads) {
    for (final implementation in selected) {
      final runs = observations
          .where(
            (r) =>
                r['implementation'] == implementation &&
                r['workload'] == workload,
          )
          .toList();
      final completed = runs.where((r) => r['duration_ms'] != null).toList();
      List<Json> perRun(String source, String key) => completed
          .where((r) => r[source] != null)
          .map((r) => <String, dynamic>{'run_id': r['run_id'], key: r[source]})
          .toList();
      groups.add({
        'implementation': implementation,
        'workload': workload,
        'attempts': runs.length,
        'completed': completed.length,
        'correctness_failures': completed
            .where(
              (r) =>
                  r['correctness'] != null &&
                  at(r, 'correctness.passed') != true,
            )
            .length,
        'equal_work_timing_eligible': completed
            .where((r) => r['equal_work_timing_eligible'] == true)
            .length,
        'injected_inputs': completed.map((r) => r['input_count']).toList(),
        'driver_deadline_misses': completed
            .map((r) => r['scheduled_inputs_missed'])
            .toList(),
        'driver_excess_inputs': completed
            .map((r) => at(r, 'input_delivery.excess'))
            .toList(),
        'cpu_percent_one_core': acrossRuns(
          completed.map((r) => r['cpu_percent_one_core']),
        ),
        'working_set_mib': acrossRuns(
          completed.map(
            (r) => number(at(r, 'working_set_bytes.p50')) / 1048576,
          ),
        ),
        'private_mib': acrossRuns(
          completed.map((r) => number(at(r, 'private_bytes.p50')) / 1048576),
        ),
        'window_available_ms': acrossRuns(
          completed.map((r) => r['window_available_ms']),
        ),
        'native_draw_by_run': completed
            .where((r) => r['native_diagnostics'] != null)
            .map(
              (r) => {
                'run_id': r['run_id'],
                'histogram': at(r, 'native_diagnostics.draw'),
                'scope': at(r, 'native_diagnostics.scope'),
              },
            )
            .toList(),
        'solid_draw_by_run': perRun('solid_draw_overlay', 'overlay'),
        'flutter_frames_by_run': perRun('flutter_frame_timing', 'frames'),
        'application_work_by_run': completed
            .map((r) => {'run_id': r['run_id'], 'work': r['application_work']})
            .toList(),
        'publication_by_run': perRun('dart_publication', 'publication'),
      });
    }
  }
  final result = <String, dynamic>{
    'run_prefix': prefix,
    'repetitions': repetitions,
    'implementations': selected,
    'summary_scope': 'All completed observations, including cadence differences and correctness failures. Memory summarizes per-run sample medians. Drawing/publication percentiles remain individual, unpooled histograms.',
    'groups': groups,
    'observations': observations,
  };
  writeJson('$reports/$prefix-summary.json', result);
  return result;
}

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final prefix = o.string('run-prefix'),
      repetitions = o.integer('repetitions', 3, 1, 100),
      selected = o.selection();
  o.done();
  final result = summarize(
    '${repositoryRoot()}/reports/comparison',
    prefix,
    repetitions,
    selected,
  );
  stdout.writeln(
    'Summarized ${(result['observations'] as List).length} observations for $prefix.',
  );
});
