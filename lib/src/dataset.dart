part of 'host.dart';

/// Records a dataset may hold. Uploads larger than one message travel as a
/// schema followed by appended slices, so this bounds memory, not transfer.
const int maxDatasetRows = 1000000;

/// Authoritative Dart records, uploaded once and updated through host transactions.
/// Public rows are immutable. Successful transactions advance [revision].
///
/// A dataset whose records exceed about 4 MiB of encoded text uploads in
/// several messages: its columns and formats go first and its records follow
/// in slices, each advancing [revision] by one, before `open`,
/// `registerDataset` or `replaceDataset` completes.
///
/// With `retainRecords: false` the Dart copy of the records is released once
/// they are uploaded: [rowCount] and edits by index keep working, native
/// validates record IDs, and [row], [cell] and [rowId] throw. Native holds
/// the only copy, which at a million records saves the application a few
/// hundred MiB.
final class TableDataset {
  TableDataset(
    this.id, {
    required List<String> columns,
    required List<List<String>> rows,
    List<String>? rowIds,
    Map<int, UiColumnFormat>? formats,
    this.retainRecords = true,
  }) : _columns = List.unmodifiable(columns),
       _rows = _copyRows(rows),
       _rowIds = rowIds?.toList(),
       _identity = rowIds != null,
       _rowCount = rows.length,
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

  /// Whether Dart keeps its own copy of the records after uploading them.
  final bool retainRecords;
  List<String> _columns;
  List<List<String>> _rows;
  List<String>? _rowIds;
  bool _identity;
  int _rowCount;
  Map<int, UiColumnFormat>? _formats;
  int _revision = 0;
  GpuiHost? _owner;

  /// The window this dataset belongs to; 0 is the main window.
  int _window = 0;
  bool _busy = false;

  int get revision => _revision;
  int get rowCount => retainRecords ? _rows.length : _rowCount;
  List<String> get columns => _columns;
  List<String> row(int index) => _records[index];
  String cell(int row, int column) => _records[row][column];

  /// The stable record ID for [index], when this dataset has record IDs.
  /// Row edits never change a record's ID; `replaceDataset` may supply a new
  /// ID set.
  String? rowId(int index) {
    if (!retainRecords) throw _notRetained();
    return _rowIds?[index];
  }

  List<List<String>> get _records {
    if (!retainRecords) throw _notRetained();
    return _rows;
  }

  StateError _notRetained() => StateError(
    'Dataset "$id" does not retain its records; construct it with '
    'retainRecords: true to read them in Dart',
  );

  /// Drops the Dart copy once native holds the records, when not retained.
  void _releaseRecords() {
    if (retainRecords) return;
    _rowCount = _rows.length;
    _rows = [];
    _rowIds = _identity ? [] : null;
  }

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

  /// Records [start] to [end] with their IDs, for a partial replacement.
  Map<String, Object> _dataRange(int start, int end) {
    if (start == 0 && end == _rows.length) return _data();
    final ids = _rowIds;
    return {
      'columns': _columns,
      'rows': _rows.sublist(start, end),
      if (ids != null) 'ids': ids.sublist(start, end),
      if (_formats != null)
        'format': {
          'columns': {
            for (final MapEntry(:key, :value) in _formats!.entries)
              '$key': value.toJson(),
          },
        },
    };
  }

  /// Records [start] to [end] as an append behind the ones already uploaded.
  Map<String, Object> _appendChange(int start, int end) => {
    'op': 'append',
    'rows': _rows.sublist(start, end),
    if (_rowIds != null) 'ids': _rowIds!.sublist(start, end),
  };

  /// Records are uploaded in messages of about this many encoded bytes; JSON
  /// escapes and non-ASCII text can triple the estimate, still under the
  /// 16 MiB message limit.
  static const int _chunkBytes = 4 << 20;

  /// Row ranges whose estimated encoded size each fits one message.
  List<(int, int)> _chunks() {
    final chunks = <(int, int)>[];
    var start = 0;
    var bytes = 0;
    for (var i = 0; i < _rows.length; i++) {
      var rowBytes = 4;
      for (final cell in _rows[i]) {
        rowBytes += cell.length + 3;
      }
      if (_rowIds != null) rowBytes += _rowIds![i].length + 3;
      if (bytes + rowBytes > _chunkBytes && i > start) {
        chunks.add((start, i));
        start = i;
        bytes = 0;
      }
      bytes += rowBytes;
    }
    chunks.add((start, _rows.length));
    return chunks;
  }

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

List<List<String>> _copyRows(List<List<String>> rows) {
  if (rows.length > maxDatasetRows) {
    throw ArgumentError(
      'Dataset requires 1..64 columns and at most $maxDatasetRows rows',
    );
  }
  return rows.map((row) => List<String>.unmodifiable(row)).toList();
}

void _validateData(List<String> columns, List<List<String>> rows) {
  if (columns.isEmpty || columns.length > 64 || rows.length > maxDatasetRows) {
    throw ArgumentError(
      'Dataset requires 1..64 columns and at most $maxDatasetRows rows',
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
    : rows = _dataset.rowCount,
      columns = _dataset._columns.length,
      identity = _dataset._identity;
  final TableDataset _dataset;
  int rows;
  final int columns;
  final bool identity;
  Set<String>? _live;

  /// Record IDs are only known here while the records are retained; native
  /// still rejects a duplicate or empty ID.
  bool get tracksIds => _dataset.retainRecords;
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
    if (!dataset.retainRecords) return;
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
    if (!dataset.retainRecords) return;
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
    if (shape.rows >= maxDatasetRows) {
      throw ArgumentError('Dataset allows at most $maxDatasetRows rows');
    }
    final record = id;
    if (shape.identity != (record != null)) {
      throw ArgumentError(
        'Insert carries a record ID exactly when the dataset has record IDs',
      );
    }
    if (record != null &&
        (record.isEmpty || (shape.tracksIds && !shape.live.add(record)))) {
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
    if (!dataset.retainRecords) {
      dataset._rowCount++;
      return;
    }
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
    if (!dataset.retainRecords) {
      dataset._rowCount--;
      return;
    }
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
    if (!dataset.retainRecords) return;
    dataset._rows.insert(to, dataset._rows.removeAt(row));
    final ids = dataset._rowIds;
    if (ids != null) ids.insert(to, ids.removeAt(row));
  }

  @override
  Map<String, Object> _toJson() => {'kind': 'move', 'row': row, 'to': to};
}

extension _DatasetTransactions on GpuiHost {
  /// Sends the records the initial message left out: a deferred dataset as
  /// one replacement, a dataset too large for one message as appended slices
  /// behind the schema already uploaded at revision 1.
  Future<void> _uploadRecords(
    TableDataset dataset,
    List<(int, int)> chunks, {
    required bool deferred,
  }) async {
    if (chunks.length == 1) {
      if (deferred) {
        await _transact(dataset, {
          'op': 'replace',
          'data': dataset._data(),
        }, () {});
      }
    } else {
      for (final (start, end) in chunks) {
        await _transact(dataset, dataset._appendChange(start, end), () {});
      }
    }
    dataset._releaseRecords();
  }

  /// Registers a dataset under an unused ID: its first slice as a replacement
  /// at revision 1, the rest appended.
  Future<void> _register(TableDataset dataset, {required int window}) async {
    final chunks = dataset._chunks();
    await _transact(
      dataset,
      {'op': 'replace', 'data': dataset._dataRange(0, chunks.first.$2)},
      () {},
      create: true,
      window: window,
    );
    for (final (start, end) in chunks.skip(1)) {
      await _transact(dataset, dataset._appendChange(start, end), () {});
    }
    dataset._releaseRecords();
  }

  Future<void> _transact(
    TableDataset dataset,
    Map<String, Object> change,
    void Function() commit, {
    bool create = false,
    int window = 0,
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
    final target = create ? window : dataset._window;
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
        (bytes, length) => target == 0
            ? _bindings.dataset(_handle, bytes, length)
            : _bindings.windows!.dataset(_handle, target, bytes, length),
        traced: target == 0,
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
        dataset._window = window;
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
