@TestOn('windows')
library;

import 'dart:async';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Dart timers publish to the real GPUI loop and shutdown releases it',
    () async {
      final dataset = TableDataset(
        'records',
        columns: ['ID', 'Value'],
        rows: List.generate(10000, (i) => ['$i', 'Row $i']),
      );
      UiNode build(String message) => UiColumn('root', [
        UiText('status', message),
        const UiButton('action', 'Action'),
        const UiInput('input', placeholder: 'Persistent input'),
        const UiTable('table', dataset: 'records'),
      ]);
      final host = await GpuiHost.open(build('Starting'), datasets: [dataset]);
      final events = <GpuiEvent>[];
      final subscription = host.events.listen(events.add);
      try {
        final firstUpdate = Completer<void>();
        Timer(const Duration(milliseconds: 100), () async {
          try {
            await host.publish(build('Timer completed'));
            firstUpdate.complete();
          } catch (error, stack) {
            firstUpdate.completeError(error, stack);
          }
        });
        await firstUpdate.future.timeout(const Duration(seconds: 10));
        await expectLater(
          host.publish(const UiTable('invalid', dataset: 'unknown')),
          throwsStateError,
        );
        await host.publish(build('Valid after rejected update'));
        await host.editDataset(dataset, [
          const CellEdit(4, 1, 'changed'),
          RowEdit(9999, ['9999', 'last']),
        ]);
        expect(dataset.revision, 2);
        expect(dataset.cell(4, 1), 'changed');
        expect(
          (await host.diagnose('cell', {
            'dataset': 'records',
            'row': 9999,
            'column': 1,
          }))['value'],
          'last',
        );
        await expectLater(host.releaseDataset(dataset), throwsStateError);
        expect(dataset.revision, 2);
        await host.replaceDataset(
          dataset,
          columns: ['ID', 'Value'],
          rows: [
            ['0', 'replacement'],
          ],
        );
        expect(dataset.revision, 3);
        expect(dataset.rowCount, 1);
        await host.publish(const UiText('empty', 'Released'));
        await host.releaseDataset(dataset);
        expect(dataset.revision, 4);
        final later = TableDataset(
          'later',
          columns: ['Value'],
          rows: [
            ['new'],
          ],
        );
        await host.registerDataset(later);
        await host.publish(const UiTable('later-table', dataset: 'later'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          events.where((e) => e.type == 'applied').map((e) => e.revision),
          containsAllInOrder([2, 4]),
        );
        expect(events.where((e) => e.type == 'error'), isEmpty);
      } finally {
        await host.close().timeout(const Duration(seconds: 10));
        await subscription.cancel();
      }
      await host.close();
      expect(() => host.publish(build('After close')), throwsStateError);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
