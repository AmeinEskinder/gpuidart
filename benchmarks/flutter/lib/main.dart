import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Flutter Windows fixture for the comparison benchmark. Same records,
/// geometry and click targets as the Rust, Shell, Solid and Dart fixtures:
/// 100,000 identical rows, three 200-pixel columns, 32-pixel rows, a
/// 320-pixel table viewport and 16-pixel text. The runner clicks at
/// (140, 69), (140, 113) and (140, 157) for the three buttons and scrolls
/// with the pointer at (400, 270).
/// The runner sets the row count; workloads other than idle and view need
/// 100,000. The view workload adds a low-cardinality sector column to group
/// by and turns the first button into the view cycle.
final rowCount =
    int.tryParse(Platform.environment['GPUIDART_BENCH_ROWS'] ?? '') ?? 100000;
final viewWorkload = Platform.environment['GPUIDART_BENCH_WORKLOAD'] == 'view';
const columnWidth = 200.0;
const rowHeight = 32.0;
const viewportHeight = 320.0;
const textStyle = TextStyle(fontSize: 16);

/// The view workload cycles the table through these stages, one per click:
/// a descending sort on the price, the sort with a filter that keeps about
/// half the records, both with a grouping by sector (a header row per group
/// with the key, the count, the average and the maximum price, as the Kit
/// table shows), and back to the plain records.
const viewStages = ['records', 'sort', 'sort+filter', 'sort+filter+group'];
const filterAbove = 5100.0;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: gpui_flutter_comparison OUTPUT_JSON');
    exit(64);
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Material(child: Benchmark(output: args.single)),
    ),
  );
}

class Benchmark extends StatefulWidget {
  const Benchmark({super.key, required this.output});

  final String output;

  @override
  State<Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<Benchmark> {
  final rows = List.generate(
    rowCount,
    (i) => [
      '$i',
      'Instrument $i',
      (100 + i / 100).toStringAsFixed(2),
      if (viewWorkload) 'Sector ${i % 12}',
    ],
  );
  // The numeric keys the view work sorts, filters and aggregates on, parsed
  // once; the Kit table parses its cells natively at each recompute.
  late final prices = viewWorkload
      ? List<double>.generate(rowCount, (i) => double.parse(rows[i][2]))
      : const <double>[];
  final controller = ScrollController();
  final buildUs = <int>[];
  final rasterUs = <int>[];
  final totalUs = <int>[];
  int? firstFrameMsSinceLaunch;
  var updates = 0;
  var cellsWritten = 0;
  var rowBuilds = 0;

  // View workload state: the stage, the displayed entries (a record index,
  // or a negative index into [headers] for a group header) and the timings.
  var stage = 0;
  List<int>? display;
  final headers = <List<String>>[];
  final viewComputeUs = <int>[];
  final viewFrameUs = <int>[];
  final viewFrameTotalUs = <int>[];
  Stopwatch? viewClock;
  var awaitingViewFrame = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_recordFrames);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_recordFrames);
    controller.dispose();
    super.dispose();
  }

  void _recordFrames(List<FrameTiming> timings) {
    if (firstFrameMsSinceLaunch == null) {
      final launch = int.tryParse(
        Platform.environment['GPUIDART_BENCH_LAUNCH_UTC_MS'] ?? '',
      );
      if (launch != null) {
        firstFrameMsSinceLaunch =
            DateTime.now().toUtc().millisecondsSinceEpoch - launch;
      }
    }
    for (final timing in timings) {
      buildUs.add(timing.buildDuration.inMicroseconds);
      rasterUs.add(timing.rasterDuration.inMicroseconds);
      totalUs.add(timing.totalSpan.inMicroseconds);
      if (awaitingViewFrame) {
        awaitingViewFrame = false;
        viewFrameTotalUs.add(timing.totalSpan.inMicroseconds);
      }
    }
  }

  void update(int count) {
    setState(() {
      updates++;
      cellsWritten += count;
      final value = 'Tick ${updates.toString().padLeft(6, '0')}';
      for (var row = 0; row < count; row++) {
        rows[row][2] = value;
      }
    });
  }

  /// One click of the view workload: the next stage's rows are computed on
  /// the UI isolate, as a Flutter application sorting its own list does, and
  /// the frame that shows them follows the `setState`.
  void cycleView() {
    final clock = Stopwatch()..start();
    stage = (stage + 1) % viewStages.length;
    updates++;
    headers.clear();
    display = switch (stage) {
      1 => _sorted(),
      2 => _filtered(_sorted()),
      3 => _grouped(_filtered(_sorted())),
      _ => null,
    };
    viewComputeUs.add(clock.elapsedMicroseconds);
    viewClock = clock;
    awaitingViewFrame = true;
    setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) {
      viewFrameUs.add(clock.elapsedMicroseconds);
    });
  }

  List<int> _sorted() {
    final order = List<int>.generate(rowCount, (i) => i);
    order.sort((a, b) => prices[b].compareTo(prices[a]));
    return order;
  }

  List<int> _filtered(List<int> order) =>
      order.where((i) => prices[i] > filterAbove).toList();

  List<int> _grouped(List<int> order) {
    final groups = <String, List<int>>{};
    for (final i in order) {
      (groups[rows[i][3]] ??= []).add(i);
    }
    final result = <int>[];
    for (final MapEntry(key: sector, value: members) in groups.entries) {
      var sum = 0.0;
      var maximum = double.negativeInfinity;
      for (final i in members) {
        sum += prices[i];
        maximum = max(maximum, prices[i]);
      }
      headers.add([
        sector,
        '${members.length}',
        (sum / members.length).toStringAsFixed(2),
        maximum.toStringAsFixed(2),
      ]);
      result.add(-headers.length);
      result.addAll(members);
    }
    return result;
  }

  int get itemCount => display?.length ?? rowCount;

  Future<void> report() async {
    final offset = controller.offset;
    final start = (offset / rowHeight).floor();
    final end = min(itemCount, ((offset + viewportHeight) / rowHeight).ceil());
    await File(widget.output).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'implementation': 'flutter',
        'rows': rowCount,
        'updates': updates,
        'cells_written': cellsWritten,
        'first_price': rows.isEmpty ? null : rows[0][2],
        'first_frame_ms_since_launch': firstFrameMsSinceLaunch,
        'visible_rows': {'start': start, 'end': end},
        'scroll_y': -offset,
        'scroll_y_convention':
            'negative ScrollController offset, the content displacement the '
            'Kit fixtures report',
        'row_builds': rowBuilds,
        if (viewWorkload)
          'view': {
            'stage': stage,
            'stage_name': viewStages[stage],
            'displayed_rows': itemCount,
            'compute_us': _distribution(viewComputeUs),
            'frame_us': _distribution(viewFrameUs),
            'frame_total_us': _distribution(viewFrameTotalUs),
            'scope':
                'per click: compute_us is the handler computing the stage on '
                'the UI isolate; frame_us runs from the handler to the post-frame '
                'callback of the frame that shows it (build, layout and paint '
                'done, raster pending); frame_total_us is that frame\'s '
                'FrameTiming total span',
          },
        'frames': {
          'scope':
              'every frame since the first, from FrameTiming; includes startup '
              'and warmup',
          'build_us': _distribution(buildUs),
          'raster_us': _distribution(rasterUs),
          'total_us': _distribution(totalUs),
        },
      }),
    );
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(
          height: 47,
          child: Padding(
            padding: EdgeInsets.only(left: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'GPUI comparison · 100,000 records',
                style: textStyle,
              ),
            ),
          ),
        ),
        viewWorkload
            ? _button('cell', 'Cycle view', cycleView)
            : _button('cell', 'Update one cell', () => update(1)),
        _button('burst', 'Update eight visible cells', () => update(8)),
        _button('report', 'Save measurements', report),
        const SizedBox(height: 8),
        _Row(
          cells: ['ID', 'Instrument', 'Price', if (viewWorkload) 'Sector'],
          header: true,
        ),
        SizedBox(
          height: viewportHeight,
          child: ListView.builder(
            controller: controller,
            itemExtent: rowHeight,
            itemCount: itemCount,
            itemBuilder: (context, index) {
              rowBuilds++;
              final entry = display == null ? index : display![index];
              if (entry < 0) {
                return _Row(cells: headers[-entry - 1], header: true);
              }
              return _Row(cells: rows[entry]);
            },
          ),
        ),
      ],
    );
  }

  Widget _button(String id, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: SizedBox(
        height: 40,
        width: 280,
        child: FilledButton.tonal(
          key: ValueKey(id),
          // The buttons are the driver's injection surface, not the measured
          // subject: without this the Material ink ripple keeps every click
          // workload animating at the display rate, which the Kit fixtures'
          // buttons do not do.
          style: const ButtonStyle(splashFactory: NoSplash.splashFactory),
          onPressed: onPressed,
          child: Text(label, style: textStyle),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.header = false});

  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? textStyle.copyWith(fontWeight: FontWeight.w600)
        : textStyle;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.black12)),
      ),
      child: Row(children: [for (final cell in cells) _cell(cell, style)]),
    );
  }

  Widget _cell(String text, TextStyle style) {
    return SizedBox(
      width: columnWidth,
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      ),
    );
  }
}

/// The same estimator the analyzer uses: the value at ceil(p * n) - 1 of the
/// sorted samples.
Map<String, Object?> _distribution(List<int> samples) {
  if (samples.isEmpty) return {'samples': 0};
  final sorted = [...samples]..sort();
  int at(double p) => sorted[max(0, (p * sorted.length).ceil() - 1)];
  return {
    'samples': sorted.length,
    'p50': at(0.50),
    'p95': at(0.95),
    'p99': at(0.99),
    'max': sorted.last,
    if (sorted.length <= 64) 'values': sorted,
    // In click order, so each sample can be read against its view stage.
    if (samples.length <= 64) 'sequence': samples,
  };
}
