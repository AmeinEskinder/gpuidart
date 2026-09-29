import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:gpuidart/gpuidart.dart';

/// The view workload cycles the table through these stages, one per click:
/// a descending sort on the price, the sort with a filter that keeps about
/// half the records, both with a grouping by sector and native aggregates,
/// and back to the plain records.
const viewStages = ['records', 'sort', 'sort+filter', 'sort+filter+group'];

UiTableView? viewForStage(int stage) => switch (stage) {
  1 => const UiTableView(sort: [UiSort(2, direction: UiSortDirection.desc)]),
  2 => const UiTableView(
    sort: [UiSort(2, direction: UiSortDirection.desc)],
    filter: [UiFilter(2, UiFilterOp.gt, '5100')],
  ),
  3 => const UiTableView(
    sort: [UiSort(2, direction: UiSortDirection.desc)],
    filter: [UiFilter(2, UiFilterOp.gt, '5100')],
    group: UiGroup(
      3,
      aggregates: [
        UiAggregate(2, UiAggregateOp.avg),
        UiAggregate(2, UiAggregateOp.max),
      ],
    ),
  ),
  _ => null,
};

Future<void> main(List<String> args) async {
  // Match the native executables' physical rendering scale before opening GPUI.
  final setDpiAwareness = DynamicLibrary.open('user32.dll')
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetProcessDpiAwarenessContext',
      );
  if (setDpiAwareness(-4) == 0) {
    throw StateError(
      'Could not select per-monitor DPI awareness for the benchmark',
    );
  }
  // The runner sets the row count; workloads other than idle and view need
  // 100,000. The view workload adds a low-cardinality sector column to group
  // by, permutes the prices so a sort has work to do (the same values, no
  // longer rising with the row index), and turns the first button into the
  // view cycle.
  final rows =
      int.tryParse(Platform.environment['GPUIDART_BENCH_ROWS'] ?? '') ?? 100000;
  final viewWorkload =
      Platform.environment['GPUIDART_BENCH_WORKLOAD'] == 'view';
  final data = TableDataset(
    'quotes',
    columns: ['ID', 'Instrument', 'Price', if (viewWorkload) 'Sector'],
    rows: List.generate(
      rows,
      (i) => [
        '$i',
        'Instrument $i',
        (100 + (viewWorkload ? (i * 7919) % rows : i) / 100).toStringAsFixed(2),
        if (viewWorkload) 'Sector ${i % 12}',
      ],
    ),
  );
  final launchUtcMs = int.tryParse(
    Platform.environment['GPUIDART_BENCH_LAUNCH_UTC_MS'] ?? '',
  );
  var stage = 0;
  final host = await GpuiHost.openView(
    () => UiColumn('main', [
      const UiText('title', 'GPUI comparison · 100,000 records'),
      UiButton('cell', viewWorkload ? 'Cycle view' : 'Update one cell'),
      const UiButton('burst', 'Update eight visible cells'),
      const UiButton('report', 'Save measurements'),
      UiTable('table', dataset: 'quotes', view: viewForStage(stage)),
    ]),
    datasets: [data],
    // The SDK's path for large datasets: the window opens first and the
    // records follow, so window availability measures the host, not the
    // upload.
    deferDatasets: true,
  );
  final readyMsSinceLaunch = launchUtcMs == null
      ? null
      : DateTime.now().toUtc().millisecondsSinceEpoch - launchUtcMs;
  var updates = 0;
  var cellsWritten = 0;
  final viewApplyUs = <int>[];
  final viewSettleUs = <int>[];
  final viewFrames = <int>[];
  final viewLongestGapUs = <int>[];
  final traceEnabled = Platform.environment['GPUIDART_INPUT_TRACE'] == '1';
  final inputTrace = <Map<String, Object?>>[];
  final traceClock = Stopwatch()..start();
  void trace(String stage, Object? sequence, Map<String, Object?> data) {
    if (traceEnabled) {
      inputTrace.add({
        'stage': stage,
        'sequence': sequence,
        'dart_elapsed_us': traceClock.elapsedMicroseconds,
        'data': data,
      });
    }
  }

  var pending = Future<void>.value();
  Future<void> handle(GpuiEvent event) async {
    if (event.type == 'error') throw StateError('$event');
    if (event.type != 'click') return;
    if (event.id == 'report') {
      final state = await host.diagnose('inspect');
      final nativeCell = data.rowCount == 0
          ? null
          : await host.diagnose('cell', {
              'dataset': data.id,
              'row': 0,
              'column': 2,
            });
      await File(args.single).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'implementation': 'dart',
          'rows': data.rowCount,
          'updates': updates,
          'cells_written': cellsWritten,
          'first_price': data.rowCount == 0 ? null : data.cell(0, 2),
          'first_frame_ms_since_launch': readyMsSinceLaunch,
          'native_first_price': nativeCell,
          if (viewWorkload)
            'view': {
              'stage': stage,
              'stage_name': viewStages[stage],
              'displayed_rows': state['tables']['table']['view']['view_rows'],
              'table': state['tables']['table'],
              'apply_us': distribution(viewApplyUs),
              'settle_us': distribution(viewSettleUs),
              'jank': {
                'longest_gap_us': distribution(viewLongestGapUs),
                'frames_during': viewFrames,
              },
              'scope':
                  'per click: apply_us runs from the click handler through '
                  'the rebuild acknowledgement, which native sends before '
                  'the view index computes off the frame thread; settle_us '
                  'runs on to the table_view event that reports the index '
                  'in place; jank counts the frames native rendered from a '
                  'mark set in the handler to that event and the longest '
                  'interval between two of them, with the pointer moving '
                  'over the rows at 60 Hz meanwhile',
            },
          if (traceEnabled) 'input_trace': inputTrace,
          'native': state,
          'publication': host.metrics.read(),
          'scope':
              'cumulative since window creation; includes startup and warmup',
        }),
      );
      await host.close();
      return;
    }
    final sequence = event.data['debug_input_sequence'];
    if (traceEnabled) {
      trace('application_handler', sequence, {
        'id': event.id,
        'update_ordinal': updates + 1,
        'target_revision': data.revision + 1,
      });
    }
    if (viewWorkload && event.id == 'cell') {
      stage = (stage + 1) % viewStages.length;
      updates++;
      await host.diagnose('frame_gaps', {'mark': true});
      final applying = Stopwatch()..start();
      await host.rebuild();
      viewApplyUs.add(applying.elapsedMicroseconds);
      await host.viewsSettled;
      viewSettleUs.add(applying.elapsedMicroseconds);
      final gaps = await host.diagnose('frame_gaps');
      viewFrames.add(gaps['frames'] as int);
      viewLongestGapUs.add(gaps['longest_gap_us'] as int);
      return;
    }
    final count = event.id == 'burst' ? 8 : 1;
    updates++;
    cellsWritten += count;
    await host.editDataset(
      data,
      List.generate(
        count,
        (row) => CellEdit(row, 2, 'Tick ${updates.toString().padLeft(6, '0')}'),
      ),
    );
    if (traceEnabled) {
      trace('applied_acknowledged', sequence, {
        'updates': updates,
        'revision': data.revision,
      });
      final nativeCell = await host.diagnose('cell', {
        'dataset': data.id,
        'row': 0,
        'column': 2,
      });
      trace('state_observed', sequence, {
        'value': data.cell(0, 2),
        'native': nativeCell,
      });
    }
  }

  final subscription = host.events.listen((event) {
    pending = pending.then((_) => handle(event)).catchError((
      Object error,
      StackTrace stack,
    ) {
      stderr.writeln('$error\n$stack');
      exitCode = 1;
      unawaited(host.close());
    });
  });
  await host.done;
  await subscription.cancel();
  if (traceEnabled) {
    await File('${args.single}.input-trace.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(inputTrace));
  }
}

/// The same estimator the analyzer uses: the value at ceil(p * n) - 1 of the
/// sorted samples.
Map<String, Object?> distribution(List<int> samples) {
  if (samples.isEmpty) return {'samples': 0};
  final sorted = [...samples]..sort();
  int at(double p) => sorted[max(0, (p * sorted.length).ceil() - 1)];
  return {
    'samples': sorted.length,
    'p50': at(0.50),
    'p95': at(0.95),
    'p99': at(0.99),
    'max': sorted.last,
    'values': sorted,
    // In click order, so each sample can be read against its view stage.
    'sequence': samples,
  };
}
