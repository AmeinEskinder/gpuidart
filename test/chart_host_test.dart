@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'dataset chart edit and view round trip without data republication',
    () async {
      final data = TableDataset(
        'history',
        columns: ['Day', 'Price'],
        rows: [
          ['Day one', '20'],
          ['Day two', '30'],
          ['Day three', '40'],
        ],
        rowIds: ['d1', 'd2', 'd3'],
      );
      var cutoff = '0';
      final host = await GpuiHost.openView(
        () => UiColumn('root', [
          for (final kind in ChartKind.values)
            UiChart(
              kind.name,
              dataset: 'history',
              series: kind,
              labelColumn: 0,
              valueColumn: 1,
              height: 100,
              view: UiTableView(filter: [UiFilter(1, UiFilterOp.ge, cutoff)]),
            ),
        ]),
        datasets: [data],
      );
      try {
        await host.diagnose('repaint', {'frames': 2});
        var chart = (await host.diagnose('inspect'))['charts']['line'];
        expect(chart['points'], hasLength(3));
        await host.editDataset(data, [const CellEdit(2, 1, '45')]);
        chart = (await host.diagnose('inspect'))['charts']['line'];
        expect(chart['points'].last['value'], 45);
        expect(chart['points'].last['record'], 'd3');
        cutoff = '40';
        await host.rebuild();
        await host.diagnose('repaint', {'frames': 2});
        chart = (await host.diagnose('inspect'))['charts']['bar'];
        expect(chart['points'], hasLength(1));
        expect(data.revision, 2);
        expect(data.rowCount, 3);
      } finally {
        await host.close();
      }
    },
  );
}
