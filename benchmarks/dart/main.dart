import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

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
  final data = TableDataset(
    'quotes',
    columns: ['ID', 'Instrument', 'Price'],
    rows: List.generate(
      100000,
      (i) => ['$i', 'Instrument $i', (100 + i / 100).toStringAsFixed(2)],
    ),
  );
  final host = await GpuiHost.openView(
    () => UiColumn('main', const [
      UiText('title', 'GPUI comparison · 100,000 records'),
      UiButton('cell', 'Update one cell'),
      UiButton('burst', 'Update eight visible cells'),
      UiButton('report', 'Save measurements'),
      UiTable('table', dataset: 'quotes'),
    ]),
    datasets: [data],
  );
  var updates = 0;
  var cellsWritten = 0;
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
      final nativeCell = await host.diagnose('cell', {
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
          'first_price': data.cell(0, 2),
          'native_first_price': nativeCell,
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
