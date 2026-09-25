import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'nodes.dart';
import 'metrics.dart';
import 'window_options.dart';
import 'windows.dart';

part 'dataset.dart';

typedef _EventNative = Void Function(Pointer<Uint8>, Size);
typedef _CreateNative = Pointer<Void> Function(
  Pointer<Uint8>,
  Size,
  Pointer<NativeFunction<_EventNative>>,
);
typedef _CreateDart = Pointer<Void> Function(
  Pointer<Uint8>,
  int,
  Pointer<NativeFunction<_EventNative>>,
);
typedef _PublishNative = Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef _PublishDart = int Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _HostNative = Void Function(Pointer<Void>);
typedef _HostDart = void Function(Pointer<Void>);
typedef _RunNative = Int32 Function(Pointer<Void>);
typedef _RunDart = int Function(Pointer<Void>);

final class _Bindings {
  _Bindings(String path) : library = DynamicLibrary.open(path);
  final DynamicLibrary library;
  late final create = library.lookupFunction<_CreateNative, _CreateDart>(
    'gd_create',
  );
  late final publish = library.lookupFunction<_PublishNative, _PublishDart>(
    'gd_publish',
  );
  late final dataset = library.lookupFunction<_PublishNative, _PublishDart>(
    'gd_dataset',
  );
  late final diagnostic = library.lookupFunction<_PublishNative, _PublishDart>(
    'gd_diagnostic',
  );
  late final close = library.lookupFunction<_HostNative, _HostDart>('gd_close');
  late final destroy = library.lookupFunction<_HostNative, _HostDart>(
    'gd_destroy',
  );
  late final run = library.lookupFunction<_RunNative, _RunDart>('gd_run');
  late final freeEvent = library
      .lookupFunction<_EventNative, void Function(Pointer<Uint8>, int)>(
        'gd_free_event',
      );
}

final class GpuiEvent {
  GpuiEvent._(this.data);
  final Map<String, dynamic> data;
  String get type => data['type'] as String;
  String? get id => data['id'] as String?;
  int? get revision => data['revision'] as int?;
  String? get value => data['value'] as String?;

  /// Native row selection, including the dataset revision used for the index.
  TableSelection? get tableSelection => type == 'table_selection'
      ? TableSelection._(
          data['id'] as String,
          data['dataset'] as String,
          data['dataset_revision'] as int,
          data['row'] as int?,
        )
      : null;
  @override
  String toString() => jsonEncode(data);
}

/// A row index is meaningful only within [datasetRevision]. Null means cleared.
final class TableSelection {
  const TableSelection._(
    this.table,
    this.dataset,
    this.datasetRevision,
    this.row,
  );
  final String table;
  final String dataset;
  final int datasetRevision;
  final int? row;
}

/// Experimental Windows host. The Dart application isolate keeps its event loop.
/// A dedicated isolate blocks inside GPUI's native UI loop.
final class GpuiHost {
  GpuiHost._(this._bindings);

  final _Bindings _bindings;
  final _events = StreamController<GpuiEvent>.broadcast();
  final _ready = Completer<void>();
  final _closed = Completer<void>();
  final _pending = <int, Completer<void>>{};
  final _publishTimers = <int, Stopwatch>{};
  final _diagnostics = <int, Completer<Map<String, dynamic>>>{};
  final _datasets = <String, TableDataset>{};
  final _dataPending = <int, Completer<void>>{};
  final _dataTimers = <int, Stopwatch>{};
  final metrics = HostMetrics();
  UiNode Function()? _builder;
  int _request = 0;
  late final NativeCallable<_EventNative> _callback;
  late final Pointer<Void> _handle;
  late final Future<void> done;
  int _revision = 1;
  bool _closing = false;

  Stream<GpuiEvent> get events => _events.stream;

  /// Tracks every execution of the application's description builder.
  static Future<GpuiHost> openView(
    UiNode Function() builder, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    GpuiWindowOptions window = const GpuiWindowOptions(),
  }) async {
    final timer = Stopwatch()..start();
    final root = builder();
    final elapsed = timer.elapsedMicroseconds;
    final host = await open(
      root,
      libraryPath: libraryPath,
      datasets: datasets,
      window: window,
    );
    host._builder = builder;
    host.metrics.descriptionBuilds = 1;
    HostMetrics.sample(host.metrics.buildMicroseconds, elapsed);
    return host;
  }

  Future<void> rebuild() {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final builder = _builder;
    if (builder == null) throw StateError('Use openView to register a builder');
    final timer = Stopwatch()..start();
    metrics.descriptionBuilds++;
    final root = builder();
    HostMetrics.sample(metrics.buildMicroseconds, timer.elapsedMicroseconds);
    return publish(root);
  }

  static Future<GpuiHost> open(
    UiNode root, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    GpuiWindowOptions window = const GpuiWindowOptions(),
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'The initial native host currently supports Windows.',
      );
    }
    final windowDescription = window.toJson();
    configureWindowsDpi();
    final sibling = File.fromUri(
      File(Platform.resolvedExecutable).parent.uri.resolve('gpuidart.dll'),
    );
    final path = File(
      libraryPath ??
          Platform.environment['GPUIDART_LIBRARY'] ??
          (const bool.fromEnvironment('gpuidart.packaged') ||
                  sibling.existsSync()
              ? sibling.path
              : 'target/debug/gpuidart.dll'),
    ).absolute.path;
    final host = GpuiHost._(_Bindings(path));
    for (final dataset in datasets) {
      if (dataset._owner != null ||
          dataset._busy ||
          host._datasets.containsKey(dataset.id)) {
        throw ArgumentError(
          'Dataset is already registered or its ID is duplicated',
        );
      }
      host._datasets[dataset.id] = dataset;
    }
    host._callback = NativeCallable<_EventNative>.listener(host._receive);
    host._handle = host._withMessage(
      {
        'snapshot': {'revision': 1, 'root': root.toJson()},
        'datasets': datasets.map((dataset) => dataset._upload()).toList(),
        'window': windowDescription,
      },
      'initial',
      (bytes, length) =>
          host._bindings.create(bytes, length, host._callback.nativeFunction),
    );
    if (host._handle == nullptr) {
      host._callback.close();
      await host._events.close();
      throw ArgumentError(
        'Invalid initial UI description or incompatible native DLL. '
        'Check node IDs and dataset schema, and build the DLL from the same SDK revision.',
      );
    }
    for (final dataset in datasets) {
      dataset._owner = host;
      dataset._revision = 1;
    }
    final result = ReceivePort();
    final nativeDone = result.first;
    try {
      await Isolate.spawn(
        _runNative,
        (path, host._handle.address, result.sendPort),
        onError: result.sendPort,
        errorsAreFatal: true,
        debugName: 'gpui-native-loop',
      );
    } catch (_) {
      for (final dataset in datasets) {
        dataset._owner = null;
      }
      result.close();
      host._bindings.destroy(host._handle);
      host._callback.close();
      await host._events.close();
      rethrow;
    }
    host.done = host._finish(nativeDone, result);
    // Register a handler immediately; callers also receive the original future.
    unawaited(host.done.catchError((Object _) {}));
    await host._ready.future;
    return host;
  }

  T _withMessage<T>(
    Map<String, Object> message,
    String kind,
    T Function(Pointer<Uint8>, int) action,
  ) {
    final timer = Stopwatch()..start();
    final data = utf8.encode(jsonEncode(message));
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      metrics.recordEncoding(kind, data.length, timer.elapsedMicroseconds);
      return action(bytes, data.length);
    } finally {
      calloc.free(bytes);
    }
  }

  /// Completes when Rust applies the snapshot. This is not a GPU presentation fence.
  Future<void> publish(UiNode root) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final revision = ++_revision;
    final accepted = Completer<void>();
    _pending[revision] = accepted;
    _publishTimers[revision] = Stopwatch()..start();
    try {
      final status = _withMessage(
        {'revision': revision, 'root': root.toJson()},
        'snapshot',
        (bytes, length) => _bindings.publish(_handle, bytes, length),
      );
      if (status != 0) {
        throw StateError('Native snapshot submission failed: $status');
      }
    } catch (_) {
      _pending.remove(revision);
      _publishTimers.remove(revision);
      rethrow;
    }
    return accepted.future;
  }

  Future<void> registerDataset(TableDataset dataset) => _transact(
    dataset,
    {'op': 'replace', 'data': dataset._data()},
    () {},
    create: true,
  );

  Future<void> editDataset(TableDataset dataset, List<TableEdit> edits) {
    final batch = List<TableEdit>.of(edits);
    if (batch.isEmpty) {
      throw ArgumentError('Dataset edit batch must be nonempty');
    }
    for (final edit in batch) {
      edit._validate(dataset);
    }
    return _transact(
      dataset,
      {'op': 'edit', 'edits': batch.map((edit) => edit._toJson()).toList()},
      () {
        for (final edit in batch) {
          edit._apply(dataset);
        }
      },
    );
  }

  Future<void> replaceDataset(
    TableDataset dataset, {
    required List<String> columns,
    required List<List<String>> rows,
  }) {
    final replacement = TableDataset(dataset.id, columns: columns, rows: rows);
    return _transact(
      dataset,
      {'op': 'replace', 'data': replacement._data()},
      () {
        dataset._columns = replacement._columns;
        dataset._rows = replacement._rows;
      },
    );
  }

  Future<void> releaseDataset(TableDataset dataset) =>
      _transact(dataset, {'op': 'release'}, () {
        dataset._owner = null;
        _datasets.remove(dataset.id);
      });

  Future<void> close() {
    if (!_closing && !_closed.isCompleted) {
      _closing = true;
      _bindings.close(_handle);
    }
    return done;
  }

  /// Opt-in native inspection and test control; no commands run during repaint.
  Future<Map<String, dynamic>> diagnose(
    String op, [
    Map<String, Object> arguments = const {},
  ]) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final request = ++_request;
    final completion = Completer<Map<String, dynamic>>();
    final data = utf8.encode(
      jsonEncode({...arguments, 'op': op, 'request': request}),
    );
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      final status = _bindings.diagnostic(_handle, bytes, data.length);
      if (status != 0) throw StateError('Diagnostic request failed: $status');
      _diagnostics[request] = completion;
    } finally {
      calloc.free(bytes);
    }
    return completion.future;
  }

  void _receive(Pointer<Uint8> bytes, int length) {
    try {
      final event = GpuiEvent._(
        jsonDecode(utf8.decode(bytes.asTypedList(length)))
            as Map<String, dynamic>,
      );
      metrics.ffiCallbacks++;
      if (event.type == 'click' ||
          event.type == 'input' ||
          event.type == 'table_selection') {
        metrics.uiCallbacks++;
      }
      if (event.type == 'diagnostic') metrics.diagnosticCallbacks++;
      switch (event.type) {
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'applied':
          final timer = _publishTimers.remove(event.revision);
          if (timer != null) {
            HostMetrics.sample(
              metrics.nativeSnapshotApplyMicroseconds,
              event.data['native_apply_us'] as int,
            );
            HostMetrics.sample(
              metrics.applyMicroseconds,
              timer.elapsedMicroseconds,
            );
          }
          _pending.remove(event.revision)?.complete();
        case 'rejected':
          _publishTimers.remove(event.revision);
          _pending
              .remove(event.revision)
              ?.completeError(StateError(event.data['message'] as String));
        case 'dataset_applied':
          final timer = _dataTimers.remove(event.data['request']);
          if (timer != null) {
            HostMetrics.sample(
              metrics.dataApplyMicroseconds,
              timer.elapsedMicroseconds,
            );
          }
          HostMetrics.sample(
            metrics.nativeDataParseMicroseconds,
            event.data['parse_us'] as int,
          );
          HostMetrics.sample(
            metrics.nativeDataApplyMicroseconds,
            event.data['apply_us'] as int,
          );
          metrics.dataRecordsChecked +=
              event.data['work']['records_checked'] as int;
          metrics.dataCellsWritten +=
              event.data['work']['cells_written'] as int;
          _dataPending.remove(event.data['request'])?.complete();
        case 'dataset_rejected':
          _dataTimers.remove(event.data['request']);
          _dataPending
              .remove(event.data['request'])
              ?.completeError(StateError(event.data['message'] as String));
        case 'diagnostic':
          _diagnostics
              .remove(event.data['request'])
              ?.complete(event.data['data'] as Map<String, dynamic>);
        case 'closed':
          _closing = true;
          if (!_closed.isCompleted) _closed.complete();
          if (!_ready.isCompleted) {
            _ready.completeError(
              StateError('Native window closed before startup'),
            );
          }
        case 'error':
          if (!_ready.isCompleted) {
            _ready.completeError(StateError(event.data['message'] as String));
          }
      }
      _events.add(event);
    } finally {
      _bindings.freeEvent(bytes, length);
    }
  }

  Future<void> _finish(Future<dynamic> nativeDone, ReceivePort result) async {
    try {
      final status = await nativeDone;
      if (status is! int) {
        if (!_ready.isCompleted) {
          _ready.completeError(StateError('Native runner failed: $status'));
        }
        throw StateError('Native runner failed: $status');
      }
      await _closed.future;
      if (status != 0) throw StateError('Native UI loop failed: $status');
    } finally {
      _closing = true;
      for (final pending in _pending.values) {
        pending.completeError(
          StateError('Host closed before the snapshot was applied'),
        );
      }
      _pending.clear();
      _publishTimers.clear();
      for (final pending in _dataPending.values) {
        pending.completeError(
          StateError('Host closed during dataset transaction'),
        );
      }
      _dataPending.clear();
      _dataTimers.clear();
      for (final dataset in _datasets.values) {
        dataset._owner = null;
      }
      _datasets.clear();
      for (final pending in _diagnostics.values) {
        pending.completeError(
          StateError('Host closed during diagnostic request'),
        );
      }
      _diagnostics.clear();
      result.close();
      _bindings.destroy(_handle);
      _callback.close();
      await _events.close();
    }
  }
}

void _runNative((String, int, SendPort) args) {
  try {
    args.$3.send(_Bindings(args.$1).run(Pointer<Void>.fromAddress(args.$2)));
  } catch (error, stack) {
    args.$3.send('$error\n$stack');
  }
}
