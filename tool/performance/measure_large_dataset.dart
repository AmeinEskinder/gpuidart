import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';

/// Opens a table over ROWS records (default 1,000,000) with the window first
/// and the records appended in slices, then sorts the view, and prints one
/// JSON record: process memory before and after the upload and the sort, the
/// upload and sort wall times, the slice count and the native counters. A
/// second argument `release` drops the Dart copy of the records after the
/// upload (`retainRecords: false`). Point GPUIDART_LIBRARY at a release
/// library; the debug build's timings are not representative.
Future<void> main(List<String> args) async {
  final rows = args.isEmpty ? 1000000 : int.parse(args.first);
  final retain = args.length < 2 || args[1] != 'release';
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
    retainRecords: retain,
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
    // The VM keeps freed heap pages until a major collection; churn enough
    // short-lived allocation to force one, then let it settle, so a released
    // Dart copy shows in the process figures.
    for (var round = 0; round < 8; round++) {
      final churn = List<List<int>>.generate(200000, (i) => List.filled(16, i));
      if (churn.length == 1) stdout.writeln(churn);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final afterSettle = memory();
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
        'retain_records': retain,
        'slices': dataset.revision - 1,
        'build_ms': buildMs,
        'open_ms': openMs,
        'sort_publish_to_inspect_ms': sortMs,
        'memory': {
          'at_start': atStart,
          'after_records': afterRecords,
          'after_upload': afterUpload,
          'after_settle': afterSettle,
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
