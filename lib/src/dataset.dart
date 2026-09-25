part of 'host.dart';

/// Authoritative Dart records, uploaded once and updated through host transactions.
/// Public rows are immutable. Successful transactions advance [revision].
final class TableDataset {
  TableDataset(
    this.id, {
    required List<String> columns,
    required List<List<String>> rows,
  }) : _columns = List.unmodifiable(columns),
       _rows = rows.map((row) => List<String>.unmodifiable(row)).toList() {
    if (id.isEmpty) throw ArgumentError('Dataset ID must be nonempty');
    _validateData(_columns, _rows);
  }

  final String id;
  List<String> _columns;
  List<List<String>> _rows;
  int _revision = 0;
  GpuiHost? _owner;
  bool _busy = false;

  int get revision => _revision;
  int get rowCount => _rows.length;
  List<String> get columns => _columns;
  List<String> row(int index) => _rows[index];
  String cell(int row, int column) => _rows[row][column];

  Map<String, Object> _data() => {'columns': _columns, 'rows': _rows};
  Map<String, Object> _upload() => {'id': id, 'revision': 1, 'data': _data()};
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

sealed class TableEdit {
  const TableEdit();
  void _validate(TableDataset dataset);
  void _apply(TableDataset dataset);
  Map<String, Object> _toJson();
}

final class CellEdit extends TableEdit {
  const CellEdit(this.row, this.column, this.value);
  final int row;
  final int column;
  final String value;

  @override
  void _validate(TableDataset dataset) {
    RangeError.checkValidIndex(row, dataset._rows, 'row');
    RangeError.checkValidIndex(column, dataset._columns, 'column');
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
  void _validate(TableDataset dataset) {
    RangeError.checkValidIndex(row, dataset._rows, 'row');
    if (values.length != dataset.columns.length) {
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
    } finally {
      _dataPending.remove(request);
      _dataTimers.remove(request);
      dataset._busy = false;
    }
  }
}
