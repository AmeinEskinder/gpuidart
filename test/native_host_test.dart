@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'dart:async';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('an incompatible native library fails before host creation', () async {
    await expectLater(
      GpuiHost.open(
        const UiText('text', 'Hello'),
        libraryPath: Platform.isWindows
            ? '${Platform.environment['SystemRoot']}/System32/kernel32.dll'
            : Platform.isMacOS
            ? '/usr/lib/libSystem.B.dylib'
            : '/lib/x86_64-linux-gnu/libc.so.6',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Incompatible GPUI-Dart library'),
        ),
      ),
    );
  });

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
        await expectLater(
          GpuiHost.open(const UiText('second', 'Unsupported second host')),
          throwsArgumentError,
        );
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
        await host.publish(
          build('With actions'),
          actions: [
            const UiAction(name: 'app.search', keys: 'ctrl+f'),
            const UiAction(
              name: 'records.add',
              keys: 'ctrl+enter',
              context: UiActionContext.node('table'),
            ),
          ],
        );
        // Structurally invalid snapshots reject synchronously at submission.
        expect(
          () => host.publish(
            build('Dangling action context'),
            actions: [
              const UiAction(
                name: 'broken',
                keys: 'ctrl+b',
                context: UiActionContext.node('missing'),
              ),
            ],
          ),
          throwsStateError,
        );
        await host.publish(build('Valid after rejected actions'));
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
        // Record IDs and a view publish through FFI and report in inspect.
        final identified = TableDataset(
          'identified',
          columns: ['sym', 'price'],
          rows: [
            ['ACME', '10.5'],
            ['BETA', '3.2'],
          ],
          rowIds: ['ACME', 'BETA'],
        );
        await host.registerDataset(identified);
        await host.publish(
          const UiTable(
            'identified-table',
            dataset: 'identified',
            view: UiTableView(
              sort: [UiSort(1, direction: UiSortDirection.asc)],
            ),
          ),
        );
        final inspected = await host.diagnose('inspect');
        final identifiedTable =
            inspected['tables']['identified-table'] as Map<String, dynamic>;
        expect(identifiedTable['view']['source_rows'], 2);
        expect(identifiedTable['view']['view_rows'], 2);
        expect(identifiedTable['view']['spec_hash'], isNotNull);
        // Cell formats upload with the dataset and render natively.
        final formatted = TableDataset(
          'formatted',
          columns: ['price'],
          rows: [
            ['10.5'],
            ['-2'],
          ],
          formats: const {
            0: UiColumnFormat(
              decimals: 2,
              rules: [
                UiFormatRule(
                  when: UiFormatCondition(UiFilterOp.lt, '0'),
                  color: UiColor.token(ThemeToken.danger),
                  icon: UiCellIcon.arrowDown,
                ),
              ],
            ),
          },
        );
        await host.registerDataset(formatted);
        await host.publish(const UiTable('fmt-table', dataset: 'formatted'));
        final cell = await host.diagnose('formatted_cell', {
          'table': 'fmt-table',
          'row': 1,
          'column': 0,
        });
        expect(cell['text'], '-2.00');
        expect(cell['color'], 'token:danger');
        expect(cell['icon'], 'arrow_down');
        expect(
          (await host.diagnose('formatted_cell', {
            'table': 'fmt-table',
            'row': 0,
            'column': 0,
          }))['text'],
          '10.50',
        );
        await expectLater(
          host.publish(
            const UiTable(
              'bad-view',
              dataset: 'identified',
              view: UiTableView(sort: [UiSort(5)]),
            ),
          ),
          throwsStateError,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          events.where((e) => e.type == 'applied').map((e) => e.revision),
          containsAllInOrder([2, 4]),
        );
        expect(events.where((e) => e.type == 'error'), isEmpty);
        final paused = host.events.listen((_) {})..pause();
        try {
          await host.close().timeout(const Duration(seconds: 3));
        } finally {
          await paused.cancel();
        }
      } finally {
        await host.close().timeout(const Duration(seconds: 10));
        await subscription.cancel();
      }
      await host.close();
      expect(() => host.publish(build('After close')), throwsStateError);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'failed initial descriptions release resources for another host',
    () async {
      final dataset = TableDataset(
        'reusable',
        columns: ['Value'],
        rows: [
          ['one'],
        ],
      );
      await expectLater(
        GpuiHost.open(
          const UiTable('table', dataset: 'missing'),
          datasets: [dataset],
        ),
        throwsArgumentError,
      );
      final host = await GpuiHost.open(
        const UiTable('table', dataset: 'reusable'),
        datasets: [dataset],
      );
      try {
        final updates = <Future<bool>>[];
        for (var i = 0; i < 256; i++) {
          try {
            updates.add(
              host
                  .publish(UiText('text', '$i'))
                  .then((_) => true, onError: (Object _) => false),
            );
          } on StateError {
            // Submission can reject when the bounded native queue is full.
            updates.add(Future.value(false));
          }
        }
        final edit = host
            .editDataset(dataset, [const CellEdit(0, 0, 'two')])
            .then((_) => true, onError: (Object _) => false);
        await host.close().timeout(const Duration(seconds: 10));
        final results = await Future.wait([...updates, edit])
            .timeout(const Duration(seconds: 3));
        expect(results.length, 257);
        expect(results, contains(true));
        await expectLater(
          host.editDataset(dataset, [const CellEdit(0, 0, 'three')]),
          throwsStateError,
        );
      } finally {
        await host.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
