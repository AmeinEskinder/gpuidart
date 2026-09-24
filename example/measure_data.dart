import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import 'app.dart';

Map<String, Object> percentiles(List<int> samples) {
  final sorted = samples.toList()..sort();
  int at(double fraction) =>
      sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * fraction).round()];
  return {
    'samples': sorted.length,
    'p50_us': at(.5),
    'p95_us': at(.95),
    'p99_us': at(.99),
  };
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Map<String, Object>> measureData(
  GpuiHost host,
  DemoApplication app,
) async {
  require(
    app.quotes.rowCount >= 100,
    'Measurement requires at least 100 records',
  );
  await Future<void>.delayed(const Duration(milliseconds: 150));
  final initial = host.metrics.read();
  final phases = <Map<String, Object>>[];
  for (final operation in ['cell', 'row', 'batch10', 'counter']) {
    Future<void> update(int i) async {
      final value = (100 + i / 100).toStringAsFixed(2);
      switch (operation) {
        case 'cell':
          await host.editDataset(app.quotes, [CellEdit(4, 2, value)]);
        case 'row':
          await host.editDataset(app.quotes, [
            RowEdit(4, ['4', 'Instrument 4', value]),
          ]);
        case 'batch10':
          await host.editDataset(
            app.quotes,
            List.generate(10, (row) => CellEdit(row, 2, value)),
          );
        case 'counter':
          app.count++;
          await host.rebuild();
      }
    }

    for (var i = 0; i < 8; i++) {
      await update(i + 500);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final before = host.metrics.read();
    final nativeBefore = await host.diagnose('inspect');
    final revision = app.quotes.revision;
    final encode = operation == 'counter'
        ? host.metrics.encodeMicroseconds
        : host.metrics.dataEncodeMicroseconds;
    final nativeParse = host.metrics.nativeDataParseMicroseconds;
    final nativeApply = operation == 'counter'
        ? host.metrics.nativeSnapshotApplyMicroseconds
        : host.metrics.nativeDataApplyMicroseconds;
    final descriptions = host.metrics.buildMicroseconds;
    final encodeStart = encode.length;
    final parseStart = nativeParse.length;
    final applyStart = nativeApply.length;
    final buildStart = descriptions.length;
    final elapsed = <int>[];
    final wireBytes = <int>[];
    const iterations = 120;
    for (var i = 0; i < iterations; i++) {
      final bytes = host.metrics.encodedBytes + host.metrics.dataBytes;
      final timer = Stopwatch()..start();
      await update(i);
      elapsed.add(timer.elapsedMicroseconds);
      wireBytes.add(host.metrics.encodedBytes + host.metrics.dataBytes - bytes);
    }
    final after = host.metrics.read();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final nativeAfter = await host.diagnose('inspect');
    final cell = await host.diagnose('cell', {
      'dataset': app.quotes.id,
      'row': 4,
      'column': 2,
    });
    final counter = operation == 'counter';
    final records = counter
        ? 0
        : operation == 'batch10'
        ? 10
        : 1;
    final cells = operation == 'row' ? 3 : records;
    int delta(String field) => (after[field] as int) - (before[field] as int);
    require(
      delta('data_records_checked') == records * iterations,
      'Dataset work did not match the edited records',
    );
    require(
      delta('data_cells_written') == cells * iterations,
      'Unexpected native cell writes',
    );
    require(
      delta('data_messages') == (counter ? 0 : iterations),
      'Unexpected dataset publication',
    );
    require(
      delta('description_builds') == (counter ? iterations : 0),
      'Dataset edits rebuilt the Dart view',
    );
    require(
      delta('encoded_snapshots') == (counter ? iterations : 0),
      'Unexpected view publication',
    );
    require(
      counter ? delta('data_bytes') == 0 : delta('encoded_bytes') == 0,
      'An update transferred unrelated data',
    );
    require(
      app.quotes.revision == revision + (counter ? 0 : iterations),
      'Dataset revision did not advance correctly',
    );
    require(
      cell['value'] == '101.19' && app.quotes.cell(4, 2) == '101.19',
      'Changed cell did not reach both data stores',
    );
    require(
      nativeBefore['tables']['quotes']['entity'] ==
          nativeAfter['tables']['quotes']['entity'],
      'Table entity was replaced',
    );
    require(
      nativeAfter['native']['data_records_checked'] -
              nativeBefore['native']['data_records_checked'] ==
          records * iterations,
      'Native record counters disagree',
    );
    require(
      nativeAfter['native']['rows_constructed'] >
          nativeBefore['native']['rows_constructed'],
      'Updates did not schedule native table rendering',
    );
    phases.add({
      'operation': operation,
      'iterations': iterations,
      'snapshot_bytes': delta('encoded_bytes'),
      'dataset_bytes': delta('data_bytes'),
      'min_bytes_per_operation': wireBytes.reduce((a, b) => a < b ? a : b),
      'max_bytes_per_operation': wireBytes.reduce((a, b) => a > b ? a : b),
      'description_builds': delta('description_builds'),
      'native_records_checked': delta('data_records_checked'),
      'native_cells_written': delta('data_cells_written'),
      'description_build': percentiles(descriptions.sublist(buildStart)),
      'encode': percentiles(encode.sublist(encodeStart)),
      'native_parse': percentiles(nativeParse.sublist(parseStart)),
      'native_apply': percentiles(nativeApply.sublist(applyStart)),
      'dart_operation_to_applied': percentiles(elapsed),
      'table_entity': nativeAfter['tables']['quotes']['entity'] as int,
      'dataset_revision': app.quotes.revision,
    });
  }
  return {
    'mode': const bool.fromEnvironment('gpuidart.packaged') ? 'aot' : 'jit',
    'records': app.quotes.rowCount,
    'initial': initial['initial']!,
    'phases': phases,
    'process': {
      'rss_bytes': ProcessInfo.currentRss,
      'peak_rss_bytes': ProcessInfo.maxRss,
    },
    'scope': 'Sequential awaited transactions after eight warmups per phase. Timings end at application acknowledgement plus Dart commit, not presentation. Rendering is allowed to coalesce updates.',
  };
}
