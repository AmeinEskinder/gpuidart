import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';

/// Opens a table over ROWS records (default 1,000,000) with the window first
/// and the records appended in slices, then sorts the view, and prints one
/// JSON record: process memory before and after the upload and the sort, the
/// upload and sort wall times, the slice count and the native counters. Point
/// GPUIDART_LIBRARY at a release library; the debug build's timings are not
/// representative.
Future<void> main(List<String> args) async {
  final rows = args.isEmpty ? 1000000 : int.parse(args.first);
  Map<String, Object?> memory() {
    final info = readRuntimeInfo();
    return {
      'rss_mib': ProcessInfo.currentRss / 1048576,
      'native': info['memory_bytes'],
    };
  }

  final atStart = memory();
  final building = Stopwatch()..start();
  final dataset = TableDataset(
    'records',
    columns: ['ID', 'Instrument', 'Price'],
    rows: List.generate(
      rows,
      (i) => ['$i', 'Instrument $i', (100 + i / 100).toStringAsFixed(2)],
    ),
    rowIds: List.generate(rows, (i) => 'r$i'),
  );
  final buildMs = building.elapsedMilliseconds;
  final afterRecords = memory();
  final opening = Stopwatch()..start();
  final host = await GpuiHost.open(
    const UiTable('table', dataset: 'records'),
    datasets: [dataset],
    deferDatasets: true,
  );
  final openMs = opening.elapsedMilliseconds;
  try {
    final afterUpload = memory();
    final inspectBefore = await host.diagnose('inspect');
    final sorting = Stopwatch()..start();
    await host.publish(
      const UiTable(
        'table',
        dataset: 'records',
        view: UiTableView(sort: [UiSort(2, direction: UiSortDirection.desc)]),
      ),
    );
    await host.diagnose('inspect');
    final sortMs = sorting.elapsedMilliseconds;
    final inspectAfter = await host.diagnose('inspect');
    final afterSort = memory();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'rows': rows,
        'slices': dataset.revision - 1,
        'build_ms': buildMs,
        'open_ms': openMs,
        'sort_publish_to_inspect_ms': sortMs,
        'memory': {
          'at_start': atStart,
          'after_records': afterRecords,
          'after_upload': afterUpload,
          'after_sort': afterSort,
        },
        'metrics': host.metrics.read(),
        'table_before_sort': inspectBefore['tables']['table'],
        'table_after_sort': inspectAfter['tables']['table'],
        'native_counters': inspectAfter['native'],
        'scope':
            'One process on one machine; open_ms includes window creation and '
            'every appended slice; the sort time spans publish, native view '
            'recompute and one inspect round trip.',
      }),
    );
  } finally {
    await host.close();
  }
}
