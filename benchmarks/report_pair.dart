import 'dart:io';

import 'src/common.dart';

String renderReport(Json summary, String prefix, String title) {
  final selected = array(summary['implementations']).cast<String>();
  const labels = {
    'rust': 'Rust + GPUI Kit',
    'dart': 'Dart AOT',
    'solid': 'GPUIX/Solid/Bun',
    'shell': 'Shell/QuickJS',
    'flutter': 'Flutter Windows',
  };
  String label(String name) => labels[name] ?? name;
  final groups = <Json>[
    for (final workload in workloads)
      for (final impl in selected)
        ...array(summary['groups']).cast<Json>().where(
          (g) => g['implementation'] == impl && g['workload'] == workload,
        ),
  ];
  String range(dynamic value, [int digits = 2]) => at(value, 'median') == null
      ? 'n/a'
      : '${number(value['median']).toStringAsFixed(digits)} [${number(value['min']).toStringAsFixed(digits)}, ${number(value['max']).toStringAsFixed(digits)}]';
  String row(List<Object?> cells) =>
      '| ${cells.map((c) => c ?? '').join(' | ')} |';
  final lines = <String>[
    '# $title',
    '',
    'Rendered from [$prefix-summary.json]($prefix-summary.json): ${summary['repetitions']} rotated repetitions of each workload in ${selected.map(label).join(', ')}. Each cell is the median across completed runs with the [min, max] range; memory is the per-run p50 of 250 ms process samples, and CPU is process time over the measured interval with one logical core as 100 percent.',
    '',
    '## Reliability',
    '',
    '| Workload | Implementation | Attempts | Completed | Correctness failures | Equal-work eligible | Driver deadline misses per run |',
    '| --- | --- | ---: | ---: | ---: | ---: | --- |',
  ];
  for (final g in groups) {
    lines.add(
      row([
        g['workload'],
        label(g['implementation']),
        g['attempts'],
        g['completed'],
        g['correctness_failures'],
        g['equal_work_timing_eligible'],
        array(g['driver_deadline_misses']).join(', '),
      ]),
    );
  }
  lines.addAll([
    '',
    '## Memory, MiB',
    '',
    '| Workload | Implementation | Working set median [min, max] | Private bytes median [min, max] |',
    '| --- | --- | ---: | ---: |',
  ]);
  for (final g in groups) {
    lines.add(
      row([
        g['workload'],
        label(g['implementation']),
        range(g['working_set_mib']),
        range(g['private_mib']),
      ]),
    );
  }
  lines.addAll([
    '',
    '## CPU, percent of one logical core',
    '',
    '| Workload | Implementation | CPU median [min, max] |',
    '| --- | --- | ---: |',
  ]);
  for (final g in groups) {
    lines.add(
      row([
        g['workload'],
        label(g['implementation']),
        range(g['cpu_percent_one_core'], 1),
      ]),
    );
  }
  lines.addAll([
    '',
    '## Window availability, ms from process launch to a discovered HWND',
    '',
    '| Implementation | Median [min, max] over every workload run |',
    '| --- | ---: |',
  ]);
  for (final impl in selected) {
    final values = groups
        .where((g) => g['implementation'] == impl)
        .map((g) => g['window_available_ms'])
        .where((v) => at(v, 'median') != null)
        .toList();
    if (values.isEmpty) continue;
    final aggregate = acrossRuns(values.map((v) => v['median']))!;
    aggregate['min'] = values
        .map((v) => number(v['min']))
        .reduce((a, b) => a < b ? a : b);
    aggregate['max'] = values
        .map((v) => number(v['max']))
        .reduce((a, b) => a > b ? a : b);
    lines.add(row([label(impl), range(aggregate, 0)]));
  }
  lines.addAll([
    '',
    '## Application frame histograms, per run',
    '',
    'Each row is one run\'s own cumulative histogram since window creation, including startup and warmup; percentiles are not pooled across runs and the estimators differ between fixtures.',
    '',
    '| Workload | Implementation | Run | Samples | p50 us | p95 us | p99 us | Max us | Source |',
    '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |',
  ]);
  for (final g in groups) {
    for (final entry in array(g['native_draw_by_run'])) {
      final h = entry['histogram'];
      if (h == null) continue;
      lines.add(
        row([
          g['workload'],
          label(g['implementation']),
          entry['run_id'],
          h['samples'],
          h['p50_us'],
          h['p95_us'],
          h['p99_us'],
          '-',
          'native draw',
        ]),
      );
    }
    for (final entry in array(g['flutter_frames_by_run'])) {
      for (final phase in ['build_us', 'raster_us', 'total_us']) {
        final h = entry['frames'][phase];
        if (h == null || number(h['samples']) == 0) continue;
        lines.add(
          row([
            g['workload'],
            label(g['implementation']),
            entry['run_id'],
            h['samples'],
            h['p50'],
            h['p95'],
            h['p99'],
            h['max'],
            'FrameTiming ${phase.replaceAll('_us', '')}',
          ]),
        );
      }
    }
  }
  lines.addAll([
    '',
    '## Application work, per run',
    '',
    '| Workload | Implementation | Run | Updates | Cells written | Rows or cells built |',
    '| --- | --- | --- | ---: | ---: | ---: |',
  ]);
  for (final g in groups) {
    for (final entry in array(g['application_work_by_run'])) {
      final w = entry['work'];
      if (w == null) continue;
      lines.add(
        row([
          g['workload'],
          label(g['implementation']),
          entry['run_id'],
          w['updates'],
          w['cells_written'],
          w['flutter_row_builds'] ??
              w['shell_cell_builds'] ??
              w['solid_row_components_created'] ??
              '',
        ]),
      );
    }
  }
  return '${lines.join('\n')}\n\n';
}

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final prefix = o.string('run-prefix'),
      title = o.string('title', 'Comparison series $prefix');
  o.done();
  final reports = '${repositoryRoot()}/reports/comparison';
  File('$reports/$prefix.md').writeAsStringSync(
    renderReport(
      readJson('$reports/$prefix-summary.json') as Json,
      prefix,
      title,
    ),
  );
  stdout.writeln('Wrote $reports/$prefix.md');
});
