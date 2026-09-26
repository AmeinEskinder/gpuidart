/// A presentation-only view of a table's dataset: filter, then stable sort.
/// The authoritative Dart dataset is never reordered. At most 4 sort keys
/// and 8 filter terms; column indices must be below 64 and within the
/// dataset's width (the host rejects wider references at publish).
final class UiTableView {
  const UiTableView({this.sort = const [], this.filter = const []});

  final List<UiSort> sort;
  final List<UiFilter> filter;

  Map<String, Object> toJson() {
    if (sort.length > 4) {
      throw ArgumentError.value(sort.length, 'sort', 'at most 4 sort keys');
    }
    if (filter.length > 8) {
      throw ArgumentError.value(filter.length, 'filter', 'at most 8 terms');
    }
    return {
      if (sort.isNotEmpty) 'sort': sort.map((key) => key.toJson()).toList(),
      if (filter.isNotEmpty)
        'filter': filter.map((term) => term.toJson()).toList(),
    };
  }
}

final class UiSort {
  const UiSort(this.column, {this.direction = UiSortDirection.asc});

  final int column;
  final UiSortDirection direction;

  Map<String, Object> toJson() {
    RangeError.checkValueInInterval(column, 0, 63, 'column');
    return {'column': column, 'direction': direction.name};
  }
}

enum UiSortDirection { asc, desc }

/// Comparisons are numeric when both the cell and [value] parse as finite
/// doubles, lexical otherwise; [UiFilterOp.contains] is a substring match.
final class UiFilter {
  const UiFilter(this.column, this.op, this.value);

  final int column;
  final UiFilterOp op;
  final String value;

  Map<String, Object> toJson() {
    RangeError.checkValueInInterval(column, 0, 63, 'column');
    return {'column': column, 'op': op.name, 'value': value};
  }
}

enum UiFilterOp { eq, ne, lt, le, gt, ge, contains }
