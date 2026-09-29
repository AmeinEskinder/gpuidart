import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';

/// The memory floor of a host with almost nothing in it: opens one window
/// over a description of one text node (and, with `--rows=N`, a table over
/// N records), lets it settle, and prints one JSON record with the process
/// memory counters and every image mapped into the process by size, so the
/// floor can be attributed to the libraries behind it. Point
/// GPUIDART_LIBRARY at a release library; the debug build maps more.
Future<void> main(List<String> args) async {
  final rows = int.parse(
    args
        .firstWhere(
          (arg) => arg.startsWith('--rows='),
          orElse: () => '--rows=0',
        )
        .substring('--rows='.length),
  );
  final atStart = readRuntimeInfo()['memory_bytes'];
  final datasets = <TableDataset>[
    if (rows > 0)
      TableDataset(
        'records',
        columns: ['ID', 'Instrument', 'Price'],
        rows: List.generate(
          rows,
          (i) => ['$i', 'Instrument $i', (100 + i / 100).toStringAsFixed(2)],
        ),
      ),
  ];
  final host = await GpuiHost.open(
    rows > 0
        ? UiColumn('main', const [
            UiText('title', 'Memory floor'),
            UiTable('table', dataset: 'records'),
          ])
        : const UiText('title', 'Memory floor'),
    datasets: datasets,
    deferDatasets: rows > 0,
  );
  try {
    final afterOpen = readRuntimeInfo()['memory_bytes'];
    // Let startup work finish and the collector run, as the dataset
    // measurement does, before reading the settled counters.
    await Future<void>.delayed(const Duration(seconds: 3));
    for (var round = 0; round < 4; round++) {
      final churn = List<List<int>>.generate(100000, (i) => List.filled(16, i));
      if (churn.length == 1) stdout.writeln(churn);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final settled = readRuntimeInfo();
    final images = (settled['loaded_images'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'rows': rows,
        'dart_rss_bytes': ProcessInfo.currentRss,
        'memory': {
          'at_start': atStart,
          'after_open': afterOpen,
          'settled': settled['memory_bytes'],
          'peak': settled['memory_peak_bytes'],
        },
        'loaded_images_total_bytes': settled['loaded_images_total_bytes'],
        'loaded_images_count': images.length,
        'largest_images': [
          for (final image in images.take(20))
            {'path': image['path'], 'size_of_image': image['size_of_image']},
        ],
        'scope':
            'one process on one machine; working set and private commit are '
            'the OS counters after a settle step; image sizes are SizeOfImage '
            '(mapped, not resident) and bound the code and data the libraries '
            'can contribute to the floor',
      }),
    );
  } finally {
    await host.close();
  }
}
