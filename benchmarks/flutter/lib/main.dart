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
const rowCount = 100000;
const columnWidth = 200.0;
const rowHeight = 32.0;
const viewportHeight = 320.0;
const textStyle = TextStyle(fontSize: 16);

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
    (i) => ['$i', 'Instrument $i', (100 + i / 100).toStringAsFixed(2)],
  );
  final controller = ScrollController();
  final buildUs = <int>[];
  final rasterUs = <int>[];
  final totalUs = <int>[];
  var updates = 0;
  var cellsWritten = 0;
  var rowBuilds = 0;

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
    for (final timing in timings) {
      buildUs.add(timing.buildDuration.inMicroseconds);
      rasterUs.add(timing.rasterDuration.inMicroseconds);
      totalUs.add(timing.totalSpan.inMicroseconds);
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

  Future<void> report() async {
    final offset = controller.offset;
    final start = (offset / rowHeight).floor();
    final end = min(rowCount, ((offset + viewportHeight) / rowHeight).ceil());
    await File(widget.output).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'implementation': 'flutter',
        'rows': rowCount,
        'updates': updates,
        'cells_written': cellsWritten,
        'first_price': rows[0][2],
        'visible_rows': {'start': start, 'end': end},
        'scroll_y': -offset,
        'scroll_y_convention':
            'negative ScrollController offset, the content displacement the '
            'Kit fixtures report',
        'row_builds': rowBuilds,
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
        _button('cell', 'Update one cell', () => update(1)),
        _button('burst', 'Update eight visible cells', () => update(8)),
        _button('report', 'Save measurements', report),
        const SizedBox(height: 8),
        const _Row(id: 'ID', name: 'Instrument', price: 'Price', header: true),
        SizedBox(
          height: viewportHeight,
          child: ListView.builder(
            controller: controller,
            itemExtent: rowHeight,
            itemCount: rowCount,
            itemBuilder: (context, index) {
              rowBuilds++;
              final row = rows[index];
              return _Row(id: row[0], name: row[1], price: row[2]);
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
  const _Row({
    required this.id,
    required this.name,
    required this.price,
    this.header = false,
  });

  final String id;
  final String name;
  final String price;
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
      child: Row(
        children: [_cell(id, style), _cell(name, style), _cell(price, style)],
      ),
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
  };
}
