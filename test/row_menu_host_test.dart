@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'row command returns the stable record through the live bridge',
    () async {
      final dataset = TableDataset(
        'records',
        columns: ['Symbol', 'Price'],
        rows: [
          ['ONE', '10'],
          ['TWO', '20'],
        ],
        rowIds: ['r0', 'r1'],
      );
      final host = await GpuiHost.open(
        UiColumn('root', [
          const UiInput('before', placeholder: 'Before'),
          const UiTable(
            'table',
            dataset: 'records',
            contextMenu: [
              UiMenuAction(
                'open',
                'Open instrument',
                action: 'instrument.open',
              ),
            ],
          ),
        ]),
        datasets: [dataset],
      );
      try {
        await host.diagnose('repaint', {'frames': 2});
        await host.diagnose('select_row', {'table': 'table', 'row': 1});
        await host.diagnose('focus', {'input': 'before'});
        await host.diagnose('key', {'key': 'tab'});
        expect(
          (await host.diagnose('inspect'))['tables']['table']['focused'],
          true,
        );
        await host.diagnose('key', {'key': 'shift-f10'});
        await host.diagnose('repaint', {'frames': 2});
        final next = host.events
            .firstWhere((e) => e.type == 'row_action')
            .timeout(const Duration(seconds: 5));
        await host.diagnose('key', {'key': 'down'});
        await host.diagnose('key', {'key': 'enter'});
        final event = await next;
        expect(event.rowAction!.record, 'r1');
        expect(event.rowAction!.datasetRevision, 1);
        expect(event.rowAction!.table, 'table');
        expect(event.rowAction!.action, 'instrument.open');
      } finally {
        await host.close();
      }
    },
  );
}
