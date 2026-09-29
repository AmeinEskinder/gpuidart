@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'dart:async';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';
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

  test(
    'publications send operations and typed native input survives them',
    () async {
      UiNode build(String message, {bool wrapped = false}) => UiColumn('root', [
        UiText('status', message),
        if (wrapped)
          UiRow('row', [
            const UiText('label', 'Name'),
            const UiInput('name', placeholder: 'Name'),
          ])
        else
          const UiInput('name', placeholder: 'Name'),
      ]);
      final host = await GpuiHost.open(build('Start'));
      try {
        await host.diagnose('focus', {'input': 'name'});
        for (final key in ['h', 'i']) {
          await host.diagnose('key', {'key': key});
        }
        final typed = await host.diagnose('inspect');
        expect(typed['inputs']['name']['text'], 'hi');
        final entity = typed['inputs']['name']['entity'];

        await host.publish(build('Changed'));
        expect(host.metrics.operationPublications, 1);
        var state = await host.diagnose('inspect');
        expect(state['labels']['status'], 'Changed');
        expect(state['inputs']['name']['text'], 'hi');
        expect(state['inputs']['name']['entity'], entity);

        await host.publish(build('Wrapped', wrapped: true));
        expect(host.metrics.operationPublications, 2);
        state = await host.diagnose('inspect');
        expect(state['labels']['label'], 'Name');
        expect(state['inputs']['name']['text'], 'hi');
        expect(state['inputs']['name']['entity'], entity);

        // A batch native cannot apply rejects asynchronously. A publication
        // queued behind it was computed against the rejected tree; the host
        // resends its whole description so it still lands, in order.
        final doomed = host.publish(
          UiColumn('root', [const UiTable('orphan', dataset: 'missing')]),
        );
        final following = host.publish(build('Pipelined'));
        await expectLater(doomed, throwsStateError);
        await following;
        expect(host.metrics.operationPublications, 4);
        expect(host.metrics.resubmittedPublications, 1);
        state = await host.diagnose('inspect');
        expect(state['labels']['status'], 'Pipelined');
        expect(state['inputs']['name']['text'], 'hi');
        expect(state['inputs']['name']['entity'], entity);

        await host.publish(build('Recovered'));
        expect(host.metrics.operationPublications, 5);
        state = await host.diagnose('inspect');
        expect(state['labels']['status'], 'Recovered');
        expect(state['inputs']['name']['entity'], entity);
        expect(host.metrics.encodedSnapshots, 6);
      } finally {
        await host.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('deferred datasets paint before their records arrive', () async {
    final dataset = TableDataset(
      'records',
      columns: ['ID', 'Value'],
      rows: List.generate(20000, (i) => ['$i', 'Row $i']),
      rowIds: List.generate(20000, (i) => 'r$i'),
    );
    final trace = GpuiTrace(capacity: 512);
    final host = await GpuiHost.open(
      const UiTable('table', dataset: 'records'),
      datasets: [dataset],
      trace: trace,
      deferDatasets: true,
    );
    try {
      expect(dataset.revision, 2);
      final state = await host.diagnose('inspect');
      expect(state['tables']['table']['row_count'], 20000);
      expect(state['tables']['table']['dataset_revision'], 2);
      await host.editDataset(dataset, [const CellEdit(5, 1, 'edited')]);
      expect(dataset.revision, 3);
    } finally {
      await host.close();
    }
    final records = (trace.toJson()['records'] as List).cast<Map>();
    final firstPaint = records.firstWhere(
      (r) => r['name'] == 'native.content_paint',
    );
    final upload = records.firstWhere(
      (r) => r['operation'] == 'dataset' && r['name'] == 'dart.request',
    );
    expect(
      (firstPaint['start'] as int) < (upload['start'] as int),
      isTrue,
      reason: 'the first content paint precedes the record upload',
    );
    expect(host.metrics.initialBytes, lessThan(2048));
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('large datasets upload in slices and stay editable', () async {
    // About 11 MB of encoded records: three slices of 4 MiB behind the
    // schema, then a two-slice replacement.
    List<List<String>> records(int count) =>
        List.generate(count, (i) => ['$i', 'x' * 60, '${i % 977}']);
    final dataset = TableDataset(
      'big',
      columns: ['ID', 'Text', 'Bucket'],
      rows: records(120000),
      rowIds: List.generate(120000, (i) => 'r$i'),
    );
    final host = await GpuiHost.open(
      const UiTable('table', dataset: 'big'),
      datasets: [dataset],
    );
    try {
      expect(dataset.revision, greaterThan(2));
      expect(host.metrics.dataMessages, dataset.revision - 1);
      expect(host.metrics.initialBytes, lessThan(4096));
      var state = await host.diagnose('inspect');
      expect(state['tables']['table']['row_count'], 120000);
      expect(state['tables']['table']['dataset_revision'], dataset.revision);
      final last = await host.diagnose('cell', {
        'dataset': 'big',
        'row': 119999,
        'column': 0,
      });
      expect(last['value'], '119999');
      await host.editDataset(dataset, [const CellEdit(119999, 2, 'edited')]);
      final edited = await host.diagnose('cell', {
        'dataset': 'big',
        'row': 119999,
        'column': 2,
      });
      expect(edited['value'], 'edited');
      final before = dataset.revision;
      await host.replaceDataset(
        dataset,
        columns: ['ID', 'Text', 'Bucket'],
        rows: records(90000),
        rowIds: List.generate(90000, (i) => 's$i'),
      );
      expect(dataset.revision, greaterThan(before + 1));
      expect(dataset.rowCount, 90000);
      expect(dataset.cell(89999, 0), '89999');
      state = await host.diagnose('inspect');
      expect(state['tables']['table']['row_count'], 90000);
      expect(state['tables']['table']['dataset_revision'], dataset.revision);
    } finally {
      await host.close();
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test(
    'datasets without a Dart copy stay editable through native checks',
    () async {
      final dataset = TableDataset(
        'lean',
        columns: ['ID', 'Text'],
        rows: List.generate(120000, (i) => ['$i', 'x' * 60]),
        rowIds: List.generate(120000, (i) => 'r$i'),
        retainRecords: false,
      );
      final host = await GpuiHost.open(
        const UiTable('table', dataset: 'lean'),
        datasets: [dataset],
      );
      try {
        expect(dataset.revision, greaterThan(2));
        expect(dataset.rowCount, 120000);
        expect(() => dataset.cell(0, 0), throwsStateError);
        await host.editDataset(dataset, [const CellEdit(119999, 1, 'edited')]);
        final edited = await host.diagnose('cell', {
          'dataset': 'lean',
          'row': 119999,
          'column': 1,
        });
        expect(edited['value'], 'edited');
        // Native still owns identity: a duplicate ID is rejected there.
        await expectLater(
          host.editDataset(dataset, [
            InsertRow(120000, ['dup', 'x'], id: 'r5'),
          ]),
          throwsStateError,
        );
        expect(dataset.rowCount, 120000);
        await host.editDataset(dataset, [
          InsertRow(120000, ['new', 'x'], id: 'fresh'),
          const DeleteRow(0),
        ]);
        expect(dataset.rowCount, 120000);
        var state = await host.diagnose('inspect');
        expect(state['tables']['table']['row_count'], 120000);
        await host.replaceDataset(
          dataset,
          columns: ['ID', 'Text'],
          rows: List.generate(30000, (i) => ['$i', 'y']),
        );
        expect(dataset.rowCount, 30000);
        expect(() => dataset.cell(0, 0), throwsStateError);
        state = await host.diagnose('inspect');
        expect(state['tables']['table']['row_count'], 30000);
        expect(state['tables']['table']['dataset_revision'], dataset.revision);
      } finally {
        await host.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  test('rich text publishes and republishes markdown', () async {
    var markdown = '# Title\n\nBody';
    UiNode build() => UiRichText('notes', markdown, selectable: true);
    final host = await GpuiHost.openView(build);
    try {
      expect((await host.diagnose('inspect'))['revision'], 1);
      markdown = '# Title\n\n- one\n- two';
      await host.rebuild();
      expect((await host.diagnose('inspect'))['revision'], 2);
    } finally {
      await host.close();
    }
  });

  test('sheets open and close by publication', () async {
    var open = true;
    UiNode build() => UiColumn('main', [
      const UiText('page', 'Page'),
      UiSheet('side', 'Details', const [
        UiText('inside', 'Inside'),
      ], open: open),
    ]);
    final host = await GpuiHost.openView(build);
    try {
      var state = await host.diagnose('inspect');
      expect(state['active_sheet'], 'side');
      open = false;
      await host.rebuild();
      state = await host.diagnose('inspect');
      expect(state['active_sheet'], isNull);
    } finally {
      await host.close();
    }
  });

  test('popovers follow a published open state', () async {
    var open = true;
    UiNode build() => UiPopover('filters', 'Filters', const [
      UiText('inside', 'Inside'),
    ], open: open);
    final host = await GpuiHost.openView(build);
    try {
      // The popup's content is part of the description either way; the
      // native test covers its visibility. Here both states must apply.
      var state = await host.diagnose('inspect');
      expect(state['revision'], 1);
      open = false;
      await host.rebuild();
      state = await host.diagnose('inspect');
      expect(state['revision'], 2);
      open = true;
      await host.rebuild();
      state = await host.diagnose('inspect');
      expect(state['revision'], 3);
    } finally {
      await host.close();
    }
  });

  test('trees show their entries and follow a published selection', () async {
    String? selected;
    UiNode build() => UiTree(
      'files',
      items: const [
        UiTreeItem(
          'src',
          'src',
          expanded: true,
          children: [UiTreeItem('main', 'main.dart')],
        ),
        UiTreeItem('license', 'LICENSE'),
      ],
      selected: selected,
      style: const UiStyle(width: UiSize.px(300), height: UiSize.px(300)),
    );
    final host = await GpuiHost.openView(build);
    try {
      var state = await host.diagnose('inspect');
      expect(state['trees']['files']['entries'], hasLength(3));
      expect(state['trees']['files']['selected'], isNull);
      selected = 'main';
      await host.rebuild();
      state = await host.diagnose('inspect');
      expect(state['trees']['files']['selected'], 'main');
    } finally {
      await host.close();
    }
  });

  test('panes lay out their children and follow published sizes', () async {
    UiNode build(double leftWidth) => UiPanes(
      'split',
      const [
        UiText('left', 'Left', style: UiStyle(width: UiSize.full)),
        UiText('right', 'Right', style: UiStyle(width: UiSize.full)),
      ],
      panes: [
        UiPane(size: leftWidth, minSize: 100, maxSize: 500),
        const UiPane(),
      ],
      style: const UiStyle(width: UiSize.px(600), height: UiSize.px(200)),
    );
    var leftWidth = 200.0;
    final host = await GpuiHost.openView(() => build(leftWidth));
    try {
      var state = await host.diagnose('inspect');
      expect(state['panes']['split'], hasLength(2));
      expect((state['panes']['split'][0] as num).toDouble(), closeTo(200, 2));
      leftWidth = 300;
      await host.rebuild();
      state = await host.diagnose('inspect');
      expect(
        (state['panes']['split'][0] as num).toDouble(),
        closeTo(300, 2),
        reason: 'a published size change resizes the pane',
      );
    } finally {
      await host.close();
    }
  });

  test('packed records carry every UTF-16 shape as native UTF-8', () async {
    // A first record past the slice estimate puts the rest in a packed
    // slice of their own, so every text shape below travels packed.
    final cells = [
      'x' * 4500000,
      'plain',
      '',
      'caf\u00e9 \u65e5\u672c\u8a9e',
      'pair \ud83d\ude00 end',
      '\udbff\udfff',
      '\u07ff\u0800\uffff',
    ];
    final dataset = TableDataset(
      'text',
      columns: ['Text'],
      rows: [
        for (final cell in cells) [cell],
      ],
      rowIds: [for (final (i, cell) in cells.indexed) 'id$i:${cell.length}'],
      retainRecords: false,
    );
    final host = await GpuiHost.open(
      const UiTable('table', dataset: 'text'),
      datasets: [dataset],
    );
    try {
      expect(dataset.revision, 3, reason: 'schema, then two packed slices');
      for (var row = 1; row < cells.length; row++) {
        final read = await host.diagnose('cell', {
          'dataset': 'text',
          'row': row,
          'column': 0,
        });
        expect(read['value'], cells[row], reason: 'row $row');
      }
      // Native alone holds the records and the IDs it decoded from the
      // same frame, so the duplicate is its rejection.
      await expectLater(
        host.editDataset(dataset, [
          InsertRow(0, ['dup'], id: 'id3:${cells[3].length}'),
        ]),
        throwsStateError,
      );
      // An unpaired surrogate is refused before any message leaves Dart.
      expect(
        () => host.editDataset(dataset, [const CellEdit(1, 0, 'lone \ud83d')]),
        throwsArgumentError,
      );
      expect(dataset.revision, 3);
    } finally {
      await host.close();
    }
    // In a packed slice the same text fails the open, which closes the
    // window rather than waiting for it.
    await expectLater(
      GpuiHost.open(
        const UiTable('table', dataset: 'text'),
        datasets: [
          TableDataset(
            'text',
            columns: ['Text'],
            rows: [
              [cells.first],
              ['lone \ud83d'],
            ],
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test(
    'large views compute off the frame thread and settle in order',
    () async {
      // Large enough that the debug library's sort outlasts an inspect round
      // trip, so the index shown right after an acknowledgement is observable.
      const rows = 150000;
      final dataset = TableDataset(
        'big',
        columns: ['ID', 'Value'],
        rows: [
          for (var i = 0; i < rows; i++) ['R$i', '${rows - i}'],
        ],
        rowIds: [for (var i = 0; i < rows; i++) 'R$i'],
      );
      final host = await GpuiHost.open(
        const UiTable(
          'table',
          dataset: 'big',
          view: UiTableView(sort: [UiSort(1, direction: UiSortDirection.asc)]),
        ),
        datasets: [dataset],
      );
      try {
        final settled = <TableViewSettled>[];
        final subscription = host.events.listen((event) {
          if (event.tableView case final view?) settled.add(view);
        });
        Future<String> shown(int row) async =>
            (await host.diagnose('formatted_cell', {
                  'table': 'table',
                  'row': row,
                  'column': 0,
                }))['text']
                as String;
        // The publication was acknowledged before the index landed; the
        // settled future and the event report it.
        await host.viewsSettled;
        var state = await host.diagnose('inspect');
        expect(state['tables']['table']['view']['pending'], false);
        expect(state['tables']['table']['view']['view_rows'], rows);
        // The upload arrives in slices, so the count of jobs and settled
        // views so far depends on the slice count; later checks are relative.
        final baseJobs = state['native']['view_jobs'] as int;
        final baseRevision = dataset.revision;
        expect(await shown(0), 'R${rows - 1}', reason: 'ascending value');
        expect(settled, isNotEmpty);
        final baseSettled = settled.length;
        expect(settled.last.table, 'table');
        expect(settled.last.rows, rows);
        expect(settled.last.datasetRevision, baseRevision);
        // A new spec is acknowledged before its index exists: the table keeps
        // showing the old order until viewsSettled, then the new one.
        await host.publish(
          const UiTable(
            'table',
            dataset: 'big',
            view: UiTableView(
              sort: [UiSort(1, direction: UiSortDirection.desc)],
            ),
          ),
        );
        state = await host.diagnose('inspect');
        expect(state['tables']['table']['view']['pending'], true);
        expect(await shown(0), 'R${rows - 1}', reason: 'still ascending');
        await host.viewsSettled;
        state = await host.diagnose('inspect');
        expect(state['tables']['table']['view']['pending'], false);
        expect(await shown(0), 'R0', reason: 'descending once settled');
        expect(settled, hasLength(baseSettled + 1));
        await host.publish(
          const UiTable(
            'table',
            dataset: 'big',
            view: UiTableView(
              sort: [UiSort(1, direction: UiSortDirection.asc)],
            ),
          ),
        );
        await host.viewsSettled;
        expect(settled, hasLength(baseSettled + 2));
        // Two edits to the sort column: the first starts a job, the second is
        // sent while it runs and applies after it, in order.
        await host.editDataset(dataset, [const CellEdit(0, 1, '0')]);
        await host.editDataset(dataset, [const CellEdit(1, 1, '${rows + 5}')]);
        expect(dataset.revision, baseRevision + 2);
        await host.viewsSettled;
        state = await host.diagnose('inspect');
        expect(state['tables']['table']['view']['pending'], false);
        expect(state['tables']['table']['dataset_revision'], baseRevision + 2);
        expect(state['native']['view_jobs'], baseJobs + 4);
        expect(
          state['native']['dataset_copies'],
          0,
          reason: 'edits waited for the job instead of copying the records',
        );
        expect(await shown(0), 'R0', reason: 'value 0 sorts first');
        expect(
          await shown(rows - 1),
          'R1',
          reason: 'the largest value sorts last',
        );
        expect(settled, hasLength(baseSettled + 4));
        expect(settled.last.datasetRevision, baseRevision + 2);
        // A view over fewer records computes in place and still reports.
        await host.replaceDataset(
          dataset,
          columns: ['ID', 'Value'],
          rows: [
            ['a', '2'],
            ['b', '1'],
          ],
          rowIds: ['a', 'b'],
        );
        await host.viewsSettled;
        expect(await shown(0), 'b');
        expect(settled, hasLength(baseSettled + 5));
        expect(settled.last.rows, 2);
        await subscription.cancel();
      } finally {
        await host.close();
      }
    },
  );

  test('structural edits keep record identity, views and selection', () async {
    final dataset = TableDataset(
      'records',
      columns: ['sym', 'price'],
      rows: [
        ['A', '3'],
        ['B', '1'],
        ['C', '2'],
      ],
      rowIds: ['a', 'b', 'c'],
    );
    final host = await GpuiHost.open(
      const UiTable(
        'table',
        dataset: 'records',
        view: UiTableView(sort: [UiSort(1, direction: UiSortDirection.desc)]),
      ),
      datasets: [dataset],
    );
    try {
      // View order by price: A, C, B. Select C.
      await host.diagnose('select_row', {'table': 'table', 'row': 1});
      var state = await host.diagnose('inspect');
      expect(state['tables']['table']['selection']['record'], 'c');

      await host.editDataset(dataset, [
        InsertRow(0, ['D', '4'], id: 'd'),
        const DeleteRow(2),
        const MoveRow(0, 2),
        const CellEdit(1, 1, '5'),
      ]);
      expect(dataset.revision, 2);
      expect(
        [for (var i = 0; i < dataset.rowCount; i++) dataset.rowId(i)],
        ['a', 'c', 'd'],
      );
      expect(dataset.row(1), ['C', '5']);
      expect(dataset.row(2), ['D', '4']);
      state = await host.diagnose('inspect');
      final table = state['tables']['table'];
      expect(table['row_count'], 3);
      expect(table['view']['view_rows'], 3);
      expect(table['selection'], {'row': 0, 'record': 'c'});
      expect(
        (await host.diagnose('formatted_cell', {
          'table': 'table',
          'row': 1,
          'column': 0,
        }))['text'],
        'D',
      );
      expect(
        (await host.diagnose('cell', {
          'dataset': 'records',
          'row': 2,
          'column': 0,
        }))['value'],
        'D',
      );

      // Validation runs before submission, in batch order.
      expect(
        () => host.editDataset(dataset, [
          InsertRow(4, ['E', '1'], id: 'e'),
        ]),
        throwsRangeError,
      );
      expect(
        () => host.editDataset(dataset, [
          InsertRow(0, ['E', '1']),
        ]),
        throwsArgumentError,
      );
      expect(
        () => host.editDataset(dataset, [
          InsertRow(0, ['E', '1'], id: 'a'),
        ]),
        throwsArgumentError,
      );
      expect(
        () =>
            host.editDataset(dataset, [const DeleteRow(2), const DeleteRow(2)]),
        throwsRangeError,
      );
      expect(dataset.revision, 2);
      expect(dataset.rowCount, 3);
    } finally {
      await host.close();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
  test(
    'secondary windows publish, route datasets and close on their own',
    () async {
      final host = await GpuiHost.open(const UiText('main', 'Main'));
      final events = <GpuiEvent>[];
      final subscription = host.events.listen(events.add);
      try {
        await expectLater(
          host.openWindow(const UiTable('orphan', dataset: 'missing')),
          throwsStateError,
        );
        final details = TableDataset(
          'details',
          columns: ['k', 'v'],
          rows: [
            ['a', '1'],
          ],
        );
        UiNode build(String title) => UiColumn('root', [
          UiText('title', title),
          const UiTable('table', dataset: 'details'),
        ]);
        final child = await host.openWindow(
          build('Child'),
          options: const GpuiWindowOptions(
            title: 'Child',
            width: 400,
            height: 300,
          ),
          datasets: [details],
        );
        // The rejected request consumed an ID; IDs are never reused.
        expect(child.id, 2);
        final before = host.metrics.operationPublications;
        await child.publish(build('Child updated'));
        expect(host.metrics.operationPublications, before + 1);
        await host.editDataset(details, [const CellEdit(0, 1, '2')]);
        expect(details.revision, 2);
        expect(
          (await child.diagnose('cell', {
            'dataset': 'details',
            'row': 0,
            'column': 1,
          }))['value'],
          '2',
        );
        expect(
          (await host.diagnose('cell', {
            'dataset': 'details',
            'row': 0,
            'column': 1,
          }))['error'],
          isA<String>(),
        );
        final extra = TableDataset(
          'extra',
          columns: ['x'],
          rows: [
            ['y'],
          ],
        );
        await child.registerDataset(extra);
        await child.publish(
          UiColumn('root', [
            const UiText('title', 'Two tables'),
            const UiTable('table', dataset: 'details'),
            const UiTable('extra-table', dataset: 'extra'),
          ]),
        );
        await host.publish(const UiText('main', 'Main still publishes'));
        await child.close();
        await child.done;
        expect(() => child.publish(build('Closed')), throwsStateError);
        await expectLater(
          host.editDataset(details, [const CellEdit(0, 1, '3')]),
          throwsStateError,
        );
        await host.publish(const UiText('main', 'Main after child closed'));
        await Future<void>.delayed(Duration.zero);
        expect(
          events
              .where((event) => event.window == child.id)
              .map((event) => event.type),
          containsAll([
            'applied',
            'dataset_applied',
            'diagnostic',
            'window_closed',
          ]),
        );
        expect(
          events.where((event) => event.type == 'applied' && event.window == 0),
          isNotEmpty,
        );
      } finally {
        await subscription.cancel();
        await host.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'patches write one node without a rebuild and yield to publication',
    () async {
      UiNode build(String status) => UiColumn('root', [
        UiText('status', status),
        const UiButton('save', 'Save'),
      ]);
      final host = await GpuiHost.openView(() => build('idle'));
      try {
        await host.patch(const UiText('status', 'saving'));
        expect((await host.diagnose('inspect'))['labels']['status'], 'saving');
        expect(host.metrics.patches, 1);
        // A rebuild carries the application's value again.
        await host.rebuild();
        expect((await host.diagnose('inspect'))['labels']['status'], 'idle');
        // So does a rebuild that hands back the same const instance the
        // patch wrote over.
        const constant = UiText('constant', 'app');
        final shell = UiColumn('shell', const [constant]);
        await host.publish(
          UiColumn('root', [shell, const UiText('status', 'idle')]),
        );
        await host.patch(const UiText('constant', 'patched'));
        expect(
          (await host.diagnose('inspect'))['labels']['constant'],
          'patched',
        );
        await host.publish(
          UiColumn('root', [shell, const UiText('status', 'idle')]),
        );
        expect((await host.diagnose('inspect'))['labels']['constant'], 'app');
        await host.publish(build('idle'));
        // Patches diff cleanly against the next publication.
        await host.patch(const UiText('status', 'saved'));
        await host.publish(build('saved'));
        expect((await host.diagnose('inspect'))['labels']['status'], 'saved');
        expect(
          () => host.patch(const UiText('missing', 'x')),
          throwsArgumentError,
        );
        expect(
          () => host.patch(const UiButton('status', 'kind change')),
          throwsArgumentError,
        );
        expect(
          () => host.patch(UiColumn('root', [const UiText('status', 'x')])),
          throwsArgumentError,
        );
        expect(host.metrics.patches, 3);
      } finally {
        await host.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
