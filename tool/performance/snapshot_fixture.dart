import 'package:gpuidart/gpuidart.dart';

/// Synthetic device-property inspector: values live in node descriptions.
/// The retained table is a state-preservation sentinel, not the workload data.
final class SnapshotFixture {
  SnapshotFixture(this.fields, {this.fixedParts = false})
    : values = List.filled(fields, 0),
      order = List.generate((fields + 31) ~/ 32, (i) => i) {
    if (fields < 32 || fields > 3072) {
      throw ArgumentError('Expected 32..3072 fields');
    }
  }
  final int fields;
  final bool fixedParts;
  final List<int> values;
  List<int> order;
  final extras = <int>[];
  var nextExtra = 0;
  var edit = 0;

  void change(String operation) {
    switch (operation) {
      case 'unchanged':
        break;
      case 'property':
        values[edit++ % fields]++;
      case 'reorder':
        order = order.reversed.toList();
      case 'insert':
        extras.add(nextExtra++);
      case 'remove':
        extras.removeLast();
      default:
        throw ArgumentError('Unknown operation $operation');
    }
  }

  UiNode section(int group) => UiColumn('section-$group', [
    UiText('heading-$group', 'Device $group'),
    for (
      var field = group * 32;
      field < (group + 1) * 32 && field < fields;
      field++
    )
      UiText(
        'field-$field',
        'Device $group / property $field: ${values[field]}',
        style: const UiStyle(
          fontSize: 12,
          foreground: UiColor.token(ThemeToken.foreground),
        ),
      ),
  ], style: UiStyle(gap: 2, height: fixedParts ? const UiSize.px(768) : null));

  UiNode build() => UiColumn('root', [
    UiInput(
      'retained-input',
      placeholder: 'Retained input',
      style: fixedParts ? const UiStyle(height: UiSize.px(32)) : null,
    ),
    const UiTable(
      'retained-table',
      dataset: 'records',
      style: UiStyle(height: UiSize.px(240)),
    ),
    for (final group in order) section(group),
    for (final extra in extras)
      UiText(
        'extra-$extra',
        'Inserted $extra',
        style: fixedParts ? const UiStyle(height: UiSize.px(24)) : null,
      ),
  ], style: const UiStyle(gap: 4));

  static TableDataset dataset() => TableDataset(
    'records',
    columns: ['ID', 'Value'],
    rows: List.generate(1000, (i) => ['$i', 'Row $i']),
    rowIds: List.generate(1000, (i) => 'record-$i'),
  );
}
