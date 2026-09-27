part of 'host.dart';

/// Authoritative Dart records, uploaded once and updated through host transactions.
/// Public rows are immutable. Successful transactions advance [revision].
final class TableDataset {
  TableDataset(
    this.id, {
    required List<String> columns,
    required List<List<String>> rows,
    List<String>? rowIds,
    Map<int, UiColumnFormat>? formats,
  }) : _columns = List.unmodifiable(columns),
       _rows = rows.map((row) => List<String>.unmodifiable(row)).toList(),
       _rowIds = rowIds?.toList(),
       _formats = formats == null
           ? null
           : Map<int, UiColumnFormat>.unmodifiable(formats) {
    if (id.isEmpty) throw ArgumentError('Dataset ID must be nonempty');
    _validateData(_columns, _rows);
    _validateIds(_rowIds, _rows.length);
    if (_formats != null) {
      for (final column in _formats!.keys) {
        RangeError.checkValueInInterval(column, 0, _columns.length - 1);
      }
    }
  }

  final String id;
  List<String> _columns;
  List<List<String>> _rows;
  List<String>? _rowIds;
  Map<int, UiColumnFormat>? _formats;
  int _revision = 0;
  GpuiHost? _owner;
  bool _busy = false;

  int get revision => _revision;
  int get rowCount => _rows.length;
  List<String> get columns => _columns;
  List<String> row(int index) => _rows[index];
  String cell(int row, int column) => _rows[row][column];

  /// The stable record ID for [index], when this dataset has record IDs.
  /// Row edits never change a record's ID; `replaceDataset` may supply a new
  /// ID set.
  String? rowId(int index) => _rowIds?[index];

  Map<String, Object> _data() => {
    'columns': _columns,
    'rows': _rows,
    'ids': ?_rowIds,
    if (_formats != null)
      'format': {
        'columns': {
          for (final MapEntry(:key, :value) in _formats!.entries)
            '$key': value.toJson(),
        },
      },
  };
  Map<String, Object> _upload() => {'id': id, 'revision': 1, 'data': _data()};

  /// The columns and formats with no records, for a deferred upload.
  Map<String, Object> _uploadSchema() => {
    'id': id,
    'revision': 1,
    'data': {
      'columns': _columns,
      'rows': const <List<String>>[],
      if (_rowIds != null) 'ids': const <String>[],
      if (_formats != null)
        'format': {
          'columns': {
            for (final MapEntry(:key, :value) in _formats!.entries)
              '$key': value.toJson(),
          },
        },
    },
  };
}

void _validateIds(List<String>? rowIds, int rowCount) {
  if (rowIds == null) return;
  if (rowIds.length != rowCount) {
    throw ArgumentError('Record IDs must parallel the rows');
  }
  final seen = <String>{};
  for (final id in rowIds) {
    if (id.isEmpty || !seen.add(id)) {
      throw ArgumentError('Record IDs must be nonempty and unique');
    }
  }
}

void _validateData(List<String> columns, List<List<String>> rows) {
  if (columns.isEmpty || columns.length > 64 || rows.length > 100000) {
    throw ArgumentError(
      'Dataset requires 1..64 columns and at most 100000 rows',
    );
  }
  if (rows.any((row) => row.length != columns.length)) {
    throw ArgumentError('Dataset row width does not match its columns');
  }
}

/// The row count and record IDs as the earlier steps of a batch leave them,
/// so each step is checked against the records it will actually see. A
/// record ID deleted earlier in the batch stays reserved until the next
/// batch, matching the native check.
final class _DatasetShape {
  _DatasetShape(this._dataset)
    : rows = _dataset._rows.length,
      columns = _dataset._columns.length,
      identity = _dataset._rowIds != null;
  final TableDataset _dataset;
  int rows;
  final int columns;
  final bool identity;
  Set<String>? _live;

  Set<String> get live => _live ??= _dataset._rowIds!.toSet();

  void checkRow(int row, String name) {
    if (row < 0 || row >= rows) throw RangeError.range(row, 0, rows - 1, name);
  }
}

/// One step of an edit batch. Steps apply in order, so a row index refers to
/// the records as the previous steps left them.
sealed class TableEdit {
  const TableEdit();
  void _validate(_DatasetShape shape);
  void _apply(TableDataset dataset);
  Map<String, Object> _toJson();
}

final class CellEdit extends TableEdit {
  const CellEdit(this.row, this.column, this.value);
  final int row;
  final int column;
  final String value;

  @override
  void _validate(_DatasetShape shape) {
    shape.checkRow(row, 'row');
    if (column < 0 || column >= shape.columns) {
      throw RangeError.range(column, 0, shape.columns - 1, 'column');
    }
  }

  @override
  void _apply(TableDataset dataset) {
    final values = dataset._rows[row].toList();
    values[column] = value;
    dataset._rows[row] = List.unmodifiable(values);
  }

  @override
  Map<String, Object> _toJson() => {
    'kind': 'cell',
    'row': row,
    'column': column,
    'value': value,
  };
}

final class RowEdit extends TableEdit {
  RowEdit(this.row, List<String> values) : values = List.unmodifiable(values);
  final int row;
  final List<String> values;

  @override
  void _validate(_DatasetShape shape) {
    shape.checkRow(row, 'row');
    if (values.length != shape.columns) {
      throw ArgumentError('Row width does not match columns');
    }
  }

  @override
  void _apply(TableDataset dataset) {
    dataset._rows[row] = values;
  }

  @override
  Map<String, Object> _toJson() => {
    'kind': 'row',
    'row': row,
    'values': values,
  };
}

/// Inserts a record before [at]; [at] equal to the row count appends. [id] is
/// required exactly when the dataset has record IDs and must be unused.
final class InsertRow extends TableEdit {
  InsertRow(this.at, List<String> values, {this.id})
    : values = List.unmodifiable(values);
  final int at;
  final List<String> values;
  final String? id;

  @override
  void _validate(_DatasetShape shape) {
    if (at < 0 || at > shape.rows) {
      throw RangeError.range(at, 0, shape.rows, 'at');
    }
    if (values.length != shape.columns) {
      throw ArgumentError('Row width does not match columns');
    }
    if (shape.rows >= 100000) {
      throw ArgumentError('Dataset allows at most 100000 rows');
    }
    final record = id;
    if (shape.identity != (record != null)) {
      throw ArgumentError(
        'Insert carries a record ID exactly when the dataset has record IDs',
      );
    }
    if (record != null && (record.isEmpty || !shape.live.add(record))) {
      throw ArgumentError.value(
        record,
        'id',
        'Record ID must be nonempty and unused',
      );
    }
    shape.rows++;
  }

  @override
  void _apply(TableDataset dataset) {
    dataset._rows.insert(at, values);
    dataset._rowIds?.insert(at, id!);
  }

  @override
  Map<String, Object> _toJson() => {
    'kind': 'insert',
    'at': at,
    'values': values,
    'id': ?id,
  };
}

/// Drops the record at [row]. In identity mode a selection on that record
/// clears; otherwise the selected view row keeps its index.
final class DeleteRow extends TableEdit {
  const DeleteRow(this.row);
  final int row;

  @override
  void _validate(_DatasetShape shape) {
    shape.checkRow(row, 'row');
    shape.rows--;
  }

  @override
  void _apply(TableDataset dataset) {
    dataset._rows.removeAt(row);
    dataset._rowIds?.removeAt(row);
  }

  @override
  Map<String, Object> _toJson() => {'kind': 'delete', 'row': row};
}

/// Moves the record at [row] so that it sits at index [to] afterwards.
final class MoveRow extends TableEdit {
  const MoveRow(this.row, this.to);
  final int row;
  final int to;

  @override
  void _validate(_DatasetShape shape) {
    shape.checkRow(row, 'row');
    shape.checkRow(to, 'to');
  }

  @override
  void _apply(TableDataset dataset) {
    dataset._rows.insert(to, dataset._rows.removeAt(row));
    final ids = dataset._rowIds;
    if (ids != null) ids.insert(to, ids.removeAt(row));
  }

  @override
  Map<String, Object> _toJson() => {'kind': 'move', 'row': row, 'to': to};
}

extension _DatasetTransactions on GpuiHost {
  Future<void> _transact(
    TableDataset dataset,
    Map<String, Object> change,
    void Function() commit, {
    bool create = false,
  }) async {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    if (dataset._busy) {
      throw StateError('Await the previous dataset transaction');
    }
    if (create
        ? dataset._owner != null || _datasets.containsKey(dataset.id)
        : dataset._owner != this) {
      throw StateError('Dataset is not available for this transaction');
    }
    final base = create ? 0 : dataset._revision;
    final revision = base + 1;
    final request = ++_request;
    _trace?._point('dart.request', 'dataset', request);
    final pending = Completer<void>();
    dataset._busy = true;
    _dataPending[request] = (
      id: dataset.id,
      revision: revision,
      completion: pending,
    );
    _dataTimers[request] = Stopwatch()..start();
    try {
      final status = _withMessage(
        {
          'request': request,
          'id': dataset.id,
          'base_revision': base,
          'revision': revision,
          'change': change,
        },
        'dataset',
        request,
        (bytes, length) => _bindings.dataset(_handle, bytes, length),
      );
      if (status != 0) {
        final error = StateError('Dataset submission failed: $status');
        if (status == -4) {
          _dataPending.remove(request);
          _fail(error, StackTrace.current);
        }
        throw error;
      }
      await _withDeadline(pending.future, 'dataset $request');
      commit();
      dataset._revision = revision;
      if (create) {
        dataset._owner = this;
        _datasets[dataset.id] = dataset;
      }
      _trace?._point('dart.commit', 'dataset', request);
    } finally {
      _dataPending.remove(request);
      _dataTimers.remove(request);
      dataset._busy = false;
    }
  }
}
