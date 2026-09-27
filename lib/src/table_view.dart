/// A presentation-only view of a table's dataset: filter, then stable sort.
/// The authoritative Dart dataset is never reordered. At most 4 sort keys
/// and 8 filter terms; column indices must be below 64 and within the
/// dataset's width (the host rejects wider references at publish).
final class UiTableView {
  const UiTableView({this.sort = const [], this.filter = const [], this.group});

  final List<UiSort> sort;
  final List<UiFilter> filter;

  /// Groups the filtered, sorted records by one column and inserts a header
  /// row per group with the key, the count and native aggregates.
  final UiGroup? group;

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
      if (group != null) 'group': group!.toJson(),
    };
  }
}

/// Groups by [column] in order of first appearance after sorting. Each
/// aggregate is computed natively over the numeric cells of its column;
/// non-numeric cells are ignored except by [UiAggregateOp.count].
final class UiGroup {
  const UiGroup(this.column, {this.aggregates = const []});
  final int column;
  final List<UiAggregate> aggregates;

  Map<String, Object> toJson() {
    RangeError.checkValueInInterval(column, 0, 63, 'column');
    if (aggregates.length > 8) {
      throw ArgumentError.value(aggregates.length, 'aggregates', 'at most 8');
    }
    return {
      'column': column,
      if (aggregates.isNotEmpty)
        'aggregates': aggregates.map((a) => a.toJson()).toList(),
    };
  }
}

final class UiAggregate {
  const UiAggregate(this.column, this.op);
  final int column;
  final UiAggregateOp op;

  Map<String, Object> toJson() {
    RangeError.checkValueInInterval(column, 0, 63, 'column');
    return {'column': column, 'op': op.name};
  }
}

enum UiAggregateOp { count, sum, avg, min, max }

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
