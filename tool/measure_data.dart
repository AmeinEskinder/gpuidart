import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final executable = File('build/windows-x64/gpuidart.exe').absolute.path;
  final environment = Map<String, String>.of(Platform.environment)
    ..remove('GPUIDART_LIBRARY');
  final cases = <Map<String, dynamic>>[];
  for (final records in [100, 10000, 100000]) {
    final result = await Process.run(
      executable,
      ['--measure-data', '--rows=$records'],
      environment: environment,
      includeParentEnvironment: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'Data measurement failed for $records records: ${result.stderr}\n${result.stdout}',
      );
    }
    final report =
        jsonDecode((result.stdout as String).trim()) as Map<String, dynamic>;
    if (report['mode'] != 'aot' || report['records'] != records) {
      throw StateError('Unexpected measurement artifact');
    }
    cases.add(report);
    stdout.writeln('PASS: $records records');
  }
  for (final sample in cases.skip(1)) {
    for (var i = 0; i < (cases.first['phases'] as List).length; i++) {
      final baseline = cases.first['phases'][i] as Map;
      final phase = sample['phases'][i] as Map;
      for (final field in [
        'snapshot_bytes',
        'dataset_bytes',
        'max_bytes_per_operation',
        'native_records_checked',
        'native_cells_written',
      ]) {
        if (phase[field] != baseline[field]) {
          throw StateError('Publication work grew with dataset size: $field');
        }
      }
    }
  }
  final report = {
    'measured_at_utc': DateTime.now().toUtc().toIso8601String(),
    'cases': cases,
  };
  await File('reports/data-publication.json')
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  final markdown = StringBuffer('''# Retained dataset publication

AOT executable and release Rust DLL, with 120 sequential awaited updates per phase after eight warmups. Cases use the same three-column table, view, viewport, values and update indices. Only record count changes. Timing ends at the native acknowledgement plus Dart state commit. Updates may coalesce into fewer rendered frames; this is not an input-to-present benchmark.

The runner asserts identical transferred bytes and native record work across 100, 10,000 and 100,000 records. Every cell phase checks the result in both Dart and Rust and confirms the existing table renders after updates.

| Records | Operation | Max bytes/update | Records checked/update | JSON encode p95 | Native apply p95 | Dart operation to applied p95 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
''');
  for (final sample in cases) {
    for (final phase in sample['phases'] as List) {
      markdown.writeln(
        '| ${sample['records']} | ${phase['operation']} | ${phase['max_bytes_per_operation']} | ${phase['native_records_checked'] ~/ phase['iterations']} | ${phase['encode']['p95_us']} us | ${phase['native_apply']['p95_us']} us | ${phase['dart_operation_to_applied']['p95_us']} us |',
      );
    }
  }
  markdown.writeln();
  markdown.write('''A cell edit sends one value. A row edit sends three values. `batch10` edits one cell in each of ten rows. A counter update sends a whole view snapshot with a dataset reference and **zero dataset bytes**. The raw report includes p50/p95/p99, native parsing, descriptions, initial upload size and process memory. Native parse/apply durations are integer microseconds, so zero means less than one microsecond.

Initial upload and explicit replacement still cost O(total records). Ordinary view descriptions, cell edits and row edits do not include or scan the full dataset. Table storage remains O(total records) in both Dart and Rust. The snapshot protocol no longer accepts inline records. Rust's table data type does not implement Clone or PartialEq.

Native allocation verification is in [data-allocations.json](data-allocations.json). It measures Rust JSON decode and transaction application separately from rendering and callbacks. Compare its identical allocation counts across dataset sizes, not its different fixture's byte count with the live application above.

The previous full-data snapshot measurements are preserved in [baseline-snapshots/summary.md](baseline-snapshots/summary.md). They are a historical local sample, not a matched input-latency comparison. Percentiles for different intervals have not been added.

Reproduce with `./tool/package.ps1` followed by `dart run tool/measure_data.dart`. See [../docs/datasets.md](../docs/datasets.md) for the API and transaction contract.
''');
  await File('reports/data-publication.md').writeAsString(markdown.toString());
  stdout.writeln(
    'PASS: transferred bytes and native record work are identical across dataset sizes. Wrote reports/data-publication.json.',
  );
}
