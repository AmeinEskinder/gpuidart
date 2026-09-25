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
  var pending = Future<void>.value();
  Future<void> handle(GpuiEvent event) async {
    if (event.type == 'error') throw StateError('$event');
    if (event.type != 'click') return;
    if (event.id == 'report') {
      final state = await host.diagnose('inspect');
      await File(args.single).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'implementation': 'dart',
          'rows': data.rowCount,
          'updates': updates,
          'cells_written': cellsWritten,
          'first_price': data.cell(0, 2),
          'native': state,
          'publication': host.metrics.read(),
          'scope':
              'cumulative since window creation; includes startup and warmup',
        }),
      );
      await host.close();
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
}
