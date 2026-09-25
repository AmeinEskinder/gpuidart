import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';

/// A trace smoke workload, not a comparative performance benchmark.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    throw ArgumentError(
      'Usage: capture_publication_trace.dart output.json [native.dll]',
    );
  }
  final output = File(args[0]).absolute;
  await output.parent.create(recursive: true);
  final trace = GpuiTrace();
  final dataset = trace.measure(
    'records',
    () => TableDataset(
      'records',
      columns: ['ID', 'Value'],
      rows: List.generate(100000, (i) => ['$i', 'Row $i']),
    ),
  );
  var counter = 0;
  UiNode build() => UiColumn('root', [
    UiText('counter', 'Updates: $counter'),
    const UiTable('table', dataset: 'records'),
  ]);
  GpuiHost? host;
  try {
    host = await GpuiHost.openView(
      build,
      datasets: [dataset],
      trace: trace,
      libraryPath: args.length == 2 ? args[1] : null,
    );
    for (var i = 0; i < 30; i++) {
      await host.editDataset(dataset, [CellEdit(99999, 1, 'Update $i')]);
      counter++;
      await host.rebuild();
    }
    final cell = await host.diagnose('cell', {
      'dataset': dataset.id,
      'row': 99999,
      'column': 1,
    });
    if (cell['value'] != 'Update 29' ||
        dataset.revision != 31 ||
        host.metrics.dataRecordsChecked != 30 ||
        host.metrics.dataCellsWritten != 30 ||
        host.metrics.encodedSnapshots != 30) {
      throw StateError('Trace workload did not complete the expected updates');
    }
  } finally {
    try {
      await host?.close();
    } finally {
      await trace.writeTo(output.path);
    }
  }
  final capture = trace.toJson();
  if ((capture['metadata'] as Map)['capture_complete'] != true) {
    throw StateError('Trace was truncated or failed; inspect its metadata');
  }
  final records = capture['records'] as List;
  for (final operation in ['snapshot', 'dataset']) {
    final acknowledgements = records.where(
      (r) =>
          r['operation'] == operation &&
          (operation != 'snapshot' || (r['request'] as int) > 1) &&
          r['name'] == 'dart.ack' &&
          r['status'] == 0,
    );
    if (acknowledgements.length != 30) {
      throw StateError('Expected 30 correlated $operation acknowledgements');
    }
  }
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'mode': const bool.fromEnvironment('dart.vm.product') ? 'aot' : 'jit',
      'rows': dataset.rowCount,
      'cell_updates': 30,
      'snapshot_updates': 30,
      'trace_records': records.length,
      'trace': output.path,
      'metrics': host.metrics.read(),
      'scope': 'Tracing smoke check; instrumentation enabled. No input-to-present measurement.',
    }),
  );
}
