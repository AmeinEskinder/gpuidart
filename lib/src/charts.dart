part of 'nodes.dart';

enum ChartKind { line, bar }

/// A read-only single series rendered natively from a dataset view.
/// Uses its last [maxPoints] candidate rows. Invalid/non-finite numbers and
/// magnitudes above 1e12 are omitted and counted in the text alternative.
/// Labels are limited to 128 Unicode scalars in the projected series.
final class UiChart extends UiNode {
  const UiChart(
    super.id, {
    required this.dataset,
    required this.series,
    required this.labelColumn,
    required this.valueColumn,
    this.maxPoints = 128,
    this.height = 220,
    this.view,
    super.style,
    super.semantics,
  });
  final String dataset;
  final ChartKind series;
  final int labelColumn;
  final int valueColumn;
  final int maxPoints;
  final double height;
  final UiTableView? view;

  @override
  Map<String, Object> props() {
    if (dataset.isEmpty ||
        utf8.encode(dataset).length > 256 ||
        labelColumn < 0 ||
        labelColumn >= 64 ||
        valueColumn < 0 ||
        valueColumn >= 64 ||
        maxPoints < 1 ||
        maxPoints > 512 ||
        !height.isFinite ||
        height < 80 ||
        height > 1024) {
      throw ArgumentError(
        'Invalid chart dataset, column, point limit or height',
      );
    }
    return {
      'kind': 'chart',
      'id': id,
      if (style != null) 'style': style!.toJson(),
      if (semantics != null) 'semantics': semantics!.toJson('chart'),
      'chart': {
        'series': series.name,
        'dataset': dataset,
        'label_column': labelColumn,
        'value_column': valueColumn,
        'max_points': maxPoints,
        'height': height,
        if (view != null) 'view': view!.toJson(),
      },
    };
  }
}
