import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('table view serializes to the wire shape and omits empty lists', () {
    const view = UiTableView(
      sort: [UiSort(1, direction: UiSortDirection.desc)],
      filter: [UiFilter(0, UiFilterOp.contains, 'AC')],
    );
    final encoded = jsonDecode(jsonEncode(view.toJson()));
    expect(encoded, {
      'sort': [
        {'column': 1, 'direction': 'desc'},
      ],
      'filter': [
        {'column': 0, 'op': 'contains', 'value': 'AC'},
      ],
    });
    expect(const UiTableView().toJson(), <String, Object>{});
    expect(const UiSort(2).toJson()['direction'], 'asc');
    expect(
      const UiTable('t', dataset: 'd', view: view).toJson()['view'],
      isNotNull,
    );
    expect(
      const UiTable('t', dataset: 'd').toJson().containsKey('view'),
      isFalse,
    );
  });

  test('table view validates term counts and column indices', () {
    expect(
      () => UiTableView(sort: List.generate(5, (i) => UiSort(i))).toJson(),
      throwsArgumentError,
    );
    expect(
      () => UiTableView(
        filter: List.generate(9, (i) => UiFilter(0, UiFilterOp.eq, '$i')),
      ).toJson(),
      throwsArgumentError,
    );
    expect(() => const UiSort(64).toJson(), throwsRangeError);
    expect(
      () => const UiFilter(-1, UiFilterOp.eq, 'x').toJson(),
      throwsRangeError,
    );
    expect(
      UiTableView(
        sort: List.generate(4, (i) => UiSort(i)),
        filter: List.generate(8, (i) => UiFilter(i, UiFilterOp.ne, 'v')),
      ).toJson(),
      isNotEmpty,
    );
  });

  test('dataset record IDs validate eagerly and read back by row', () {
    final dataset = TableDataset(
      'records',
      columns: ['sym'],
      rows: [
        ['ACME'],
        ['BETA'],
      ],
      rowIds: ['ACME', 'BETA'],
    );
    expect(dataset.rowId(0), 'ACME');
    expect(dataset.rowId(1), 'BETA');

    for (final ids in [
      ['ACME'],
      ['ACME', 'ACME'],
      ['ACME', ''],
    ]) {
      expect(
        () => TableDataset(
          'bad',
          columns: ['sym'],
          rows: [
            ['ACME'],
            ['BETA'],
          ],
          rowIds: ids,
        ),
        throwsArgumentError,
        reason: '$ids',
      );
    }
    expect(TableDataset('plain', columns: ['sym'], rows: []).rowId(0), isNull);
  });
}
