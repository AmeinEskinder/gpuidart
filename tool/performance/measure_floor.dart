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
    // Let startup work finish before reading the settled counters. Nothing
    // provokes the collector: churning allocation in an idle process grows
    // the Dart heap and would report that growth as the floor; the dataset
    // measurement covers the released-copy case.
    await Future<void>.delayed(const Duration(seconds: 3));
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
        'working_set_pages': settled['working_set_pages'],
        'largest_images': [
          for (final image in images.take(20))
            {
              'path': image['path'],
              'size_of_image': image['size_of_image'],
              'resident_bytes': image['resident_bytes'],
              'resident_shared_bytes': image['resident_shared_bytes'],
            },
        ],
        'scope':
            'one process on one machine; working set and private commit are '
            'the OS counters after a settle step; image sizes are SizeOfImage '
            '(mapped, not resident) and bound the code and data the libraries '
            'can contribute to the floor; resident bytes come from a '
            'working-set walk that attributes each page in memory to the '
            'image whose mapping holds it, and working_set_pages splits the '
            'walk into shared and private pages and pages outside every image',
      }),
    );
  } finally {
    await host.close();
  }
}
