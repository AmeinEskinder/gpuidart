import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('dataset snapshots caller-owned lists and rejects invalid schemas', () {
    final columns = ['Value'];
    final row = ['日本語'];
    final rows = [row];
    final dataset = TableDataset('records', columns: columns, rows: rows);
    columns[0] = 'Changed';
    row[0] = 'Changed';
    rows.clear();
    expect(dataset.columns, ['Value']);
    expect(dataset.row(0), ['日本語']);
    expect(dataset.revision, 0);
    expect(() => dataset.columns.add('extra'), throwsUnsupportedError);
    expect(() => dataset.row(0)[0] = 'changed', throwsUnsupportedError);
    for (final invalid in <(String, List<String>, List<List<String>>)>[
      ('', ['Value'], []),
      ('records', [], []),
      (
        'records',
        ['A'],
        [
          ['A', 'B'],
        ],
      ),
      ('records', List.filled(65, 'A'), []),
    ]) {
      expect(
        () => TableDataset(invalid.$1, columns: invalid.$2, rows: invalid.$3),
        throwsArgumentError,
      );
    }
  });

  test(
    'snapshot encoding retains table references without publishing records',
    () {
      final children = <UiNode>[
        const UiText('text', '日本語 "quoted"\n'),
        const UiTable('table', dataset: 'records'),
      ];
      final root = UiColumn('root', children);
      children.clear();
      final encoded =
          jsonDecode(jsonEncode(root.toJson())) as Map<String, dynamic>;
      expect(encoded['children'], [
        {'kind': 'text', 'id': 'text', 'text': '日本語 "quoted"\n'},
        {'kind': 'table', 'id': 'table', 'dataset': 'records'},
      ]);
    },
  );

  test('window rejects invalid dimensions before FFI', () {
    for (final options in [
      const GpuiWindowOptions(title: ' '),
      const GpuiWindowOptions(width: double.nan),
      const GpuiWindowOptions(height: double.infinity),
      const GpuiWindowOptions(width: 319),
      const GpuiWindowOptions(height: 8193),
    ]) {
      expect(options.toJson, throwsArgumentError);
    }
    expect(
      const GpuiWindowOptions(width: 320, height: 240).toJson()['height'],
      240,
    );
  });
}
