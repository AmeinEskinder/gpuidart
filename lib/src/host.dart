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
import 'native_event.dart';

part 'dataset.dart';
part 'tracing.dart';

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
  _Bindings(String path) : library = DynamicLibrary.open(path) {
    const expected = 1;
    int version;
    try {
      version = library.lookupFunction<Uint32 Function(), int Function()>(
        'gd_abi_version',
      )();
    } on ArgumentError {
      throw StateError(
        'Incompatible GPUI-Dart library at $path: missing ABI version. '
        'Rebuild the native DLL with this SDK.',
      );
    }
    if (version != expected) {
      throw StateError(
        'Incompatible GPUI-Dart library at $path: ABI $version, expected $expected. '
        'Rebuild the native DLL with this SDK.',
      );
    }
  }
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
  GpuiHost._(
    this._bindings,
    this.requestTimeout,
    this.shutdownTimeout,
    this._trace,
  );

  final _Bindings _bindings;
  final GpuiTrace? _trace;

  /// Deadline for ready and native acknowledgements. A timeout closes the host.
  final Duration requestTimeout;

  /// Deadline for shutdown reporting. Native memory is retained until run exits.
  final Duration shutdownTimeout;
  final _events = StreamController<GpuiEvent>.broadcast();
  final _ready = Completer<void>();
  final _closed = Completer<void>();
  final _pending = <int, Completer<void>>{};
  final _publishTimers = <int, Stopwatch>{};
  final _diagnostics = <int, Completer<Map<String, dynamic>>>{};
  final _datasets = <String, TableDataset>{};
  final _dataPending =
      <int, ({String id, int revision, Completer<void> completion})>{};
  final _dataTimers = <int, Stopwatch>{};
  final metrics = HostMetrics();
  UiNode Function()? _builder;
  int _request = 0;
  late final NativeCallable<_EventNative> _callback;
  late final Pointer<Void> _handle;
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  Timer? _shutdownDeadline;
  Object? _failure;
  StackTrace? _failureStack;
  int _revision = 1;
  bool _closing = false;

  Stream<GpuiEvent> get events => _events.stream;

  /// Tracks every execution of the application's description builder.
  static Future<GpuiHost> openView(
    UiNode Function() builder, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    GpuiWindowOptions window = const GpuiWindowOptions(),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 10),
    GpuiTrace? trace,
  }) async {
    trace?._ensureUnclaimed();
    final timer = Stopwatch()..start();
    final root = trace == null
        ? builder()
        : trace._measure('dart.build', 'initial', 1, builder);
    final elapsed = timer.elapsedMicroseconds;
    final host = await open(
      root,
      libraryPath: libraryPath,
      datasets: datasets,
      window: window,
      requestTimeout: requestTimeout,
      shutdownTimeout: shutdownTimeout,
      trace: trace,
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
    final root = _trace == null
        ? builder()
        : _trace._measure('dart.build', 'snapshot', _revision + 1, builder);
    HostMetrics.sample(metrics.buildMicroseconds, timer.elapsedMicroseconds);
    return publish(root);
  }

  static Future<GpuiHost> open(
    UiNode root, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    GpuiWindowOptions window = const GpuiWindowOptions(),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 10),
    GpuiTrace? trace,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'The initial native host currently supports Windows.',
      );
    }
    if (requestTimeout <= Duration.zero || shutdownTimeout <= Duration.zero) {
      throw ArgumentError('Host deadlines must be positive');
    }
    final windowDescription = window.toJson();
    trace?._claim();
    trace?._point('dart.request', 'initial', 1);
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
    final bindings = trace == null
        ? _Bindings(path)
        : trace._measure('dart.library', 'initial', 1, () => _Bindings(path));
    final nativeTrace = trace == null
        ? null
        : _NativeTraceBindings(bindings.library);
    final host = GpuiHost._(bindings, requestTimeout, shutdownTimeout, trace);
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
    final describeStart = trace?._clock.now();
    final initial = <String, Object>{
      'snapshot': {'revision': 1, 'root': root.toJson()},
      'datasets': datasets.map((dataset) => dataset._upload()).toList(),
      'window': windowDescription,
    };
    if (describeStart != null) {
      trace!._span('dart.describe', 'initial', 1, describeStart);
    }
    host._callback = NativeCallable<_EventNative>.listener(host._receive);
    Pointer<Void> created = nullptr;
    try {
      created = host._handle = host._withMessage(
        initial,
        'initial',
        1,
        (bytes, length) =>
            host._bindings.create(bytes, length, host._callback.nativeFunction),
      );
      if (host._handle == nullptr) {
        throw ArgumentError(
          'Native host creation rejected. Check node IDs and dataset schema; '
          'only one GPUI host may be active in a process.',
        );
      }
      if (nativeTrace != null) {
        if (nativeTrace.enable(host._handle, trace!.capacity) != 0) {
          throw StateError('Native trace enable failed');
        }
        trace._attach(() => nativeTrace.snapshot(bindings, host._handle));
      }
    } catch (_) {
      trace?._finish();
      if (created != nullptr) bindings.destroy(created);
      host._callback.close();
      await host._events.close();
      rethrow;
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
        onExit: result.sendPort,
        errorsAreFatal: true,
        debugName: 'gpui-native-loop',
      );
    } catch (_) {
      for (final dataset in datasets) {
        dataset._owner = null;
      }
      result.close();
      trace?._finish();
      host._bindings.destroy(host._handle);
      host._callback.close();
      await host._events.close();
      rethrow;
    }
    unawaited(host._finish(nativeDone, result));
    // Register a handler immediately; callers also receive the original future.
    unawaited(host.done.catchError((Object _) {}));
    try {
      await host._withDeadline(host._ready.future, 'startup');
    } catch (_) {
      await host.done.catchError((Object _) {});
      rethrow;
    }
    return host;
  }

  T _withMessage<T>(
    Map<String, Object> message,
    String kind,
    int request,
    T Function(Pointer<Uint8>, int) action,
  ) {
    final timer = Stopwatch()..start();
    final encodingStart = _trace?._clock.now();
    final data = utf8.encode(jsonEncode(message));
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      metrics.recordEncoding(kind, data.length, timer.elapsedMicroseconds);
      if (encodingStart != null) {
        _trace!._span(
          'dart.encode',
          kind,
          request,
          encodingStart,
          bytes: data.length,
        );
      }
      final ffiStart = _trace?._clock.now();
      int? status;
      try {
        final result = action(bytes, data.length);
        status = result is int ? result : null;
        return result;
      } catch (_) {
        status = -1;
        rethrow;
      } finally {
        if (ffiStart != null) {
          _trace!._span(
            'dart.ffi',
            kind,
            request,
            ffiStart,
            bytes: data.length,
            status: status,
          );
        }
      }
    } finally {
      calloc.free(bytes);
    }
  }

  /// Completes when Rust applies the snapshot. This is not a GPU presentation fence.
  Future<void> publish(UiNode root) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final revision = ++_revision;
    _trace?._point('dart.request', 'snapshot', revision);
    final accepted = Completer<void>();
    _pending[revision] = accepted;
    _publishTimers[revision] = Stopwatch()..start();
    var status = 0;
    try {
      final rootDescription = _trace == null
          ? root.toJson()
          : _trace._measure('dart.describe', 'snapshot', revision, root.toJson);
      status = _withMessage(
        {'revision': revision, 'root': rootDescription},
        'snapshot',
        revision,
        (bytes, length) => _bindings.publish(_handle, bytes, length),
      );
      if (status != 0) {
        throw StateError('Native snapshot submission failed: $status');
      }
    } catch (error, stack) {
      _pending.remove(revision);
      _publishTimers.remove(revision);
      if (status == -4) _fail(error, stack);
      rethrow;
    }
    return _withDeadline(accepted.future, 'snapshot $revision');
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
      _beginClose();
    }
    return done;
  }

  void _beginClose() {
    if (_done.isCompleted) return;
    if (!_closing) {
      _closing = true;
      _trace?._point('dart.close', 'close', 0);
      _bindings.close(_handle);
    }
    _shutdownDeadline ??= Timer(shutdownTimeout, () {
      final error = TimeoutException(
        'Native runner did not finish shutdown; '
        'its memory is retained until it exits',
        shutdownTimeout,
      );
      _recordFailure(error, StackTrace.current);
      if (!_done.isCompleted) _done.completeError(_failure!, _failureStack);
    });
  }

  Future<T> _withDeadline<T>(Future<T> future, String operation) async {
    try {
      return await future.timeout(requestTimeout);
    } on TimeoutException {
      final error = TimeoutException(
        'No native acknowledgement for $operation; '
        'the application outcome is unknown and the host is closing',
        requestTimeout,
      );
      _fail(error, StackTrace.current);
      throw error;
    }
  }

  void _recordFailure(Object error, StackTrace stack) {
    if (_failure == null) {
      _trace?._point('dart.failure', 'failure', 0);
      _failure = error;
      _failureStack = stack;
      _events.add(
        GpuiEvent._(Map.unmodifiable({'type': 'error', 'message': '$error'})),
      );
    }
    _settlePending(error, stack);
  }

  void _fail(Object error, StackTrace stack) {
    _recordFailure(error, stack);
    _beginClose();
  }

  void _settlePending(Object error, [StackTrace? stack]) {
    if (!_ready.isCompleted) _ready.completeError(error, stack);
    for (final pending in _pending.values) {
      pending.completeError(error, stack);
    }
    _pending.clear();
    _publishTimers.clear();
    for (final pending in _dataPending.values) {
      pending.completion.completeError(error, stack);
    }
    _dataPending.clear();
    _dataTimers.clear();
    for (final pending in _diagnostics.values) {
      pending.completeError(error, stack);
    }
    _diagnostics.clear();
  }

  /// Opt-in native inspection and test control; no commands run during repaint.
  Future<Map<String, dynamic>> diagnose(
    String op, [
    Map<String, Object> arguments = const {},
  ]) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final request = ++_request;
    _trace?._point('dart.request', 'diagnostic', request);
    final completion = Completer<Map<String, dynamic>>();
    final status = _withMessage(
      {...arguments, 'op': op, 'request': request},
      'diagnostic',
      request,
      (bytes, length) => _bindings.diagnostic(_handle, bytes, length),
    );
    if (status != 0) {
      final error = StateError('Diagnostic request failed: $status');
      if (status == -4) _fail(error, StackTrace.current);
      throw error;
    }
    _diagnostics[request] = completion;
    return _withDeadline(completion.future, 'diagnostic $request');
  }

  void _receive(Pointer<Uint8> bytes, int length) {
    try {
      final received = _trace?._clock.now();
      if (bytes == nullptr || length <= 0 || length > 16 * 1024 * 1024) {
        throw const FormatException('Invalid native event buffer');
      }
      final event = GpuiEvent._(decodeNativeEvent(bytes.asTypedList(length)));
      if (received != null) _trace!._received(event.data, received, length);
      if (_failure != null && event.type != 'closed') return;
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
          final pending = _dataPending[event.data['request']];
          if (pending != null &&
              (pending.id != event.id || pending.revision != event.revision)) {
            throw const FormatException(
              'Dataset acknowledgement identity mismatch',
            );
          }
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
          _dataPending.remove(event.data['request'])?.completion.complete();
        case 'dataset_rejected':
          _dataTimers.remove(event.data['request']);
          _dataPending
              .remove(event.data['request'])
              ?.completion
              .completeError(StateError(event.data['message'] as String));
        case 'diagnostic':
          _diagnostics
              .remove(event.data['request'])
              ?.complete(event.data['data'] as Map<String, dynamic>);
        case 'closed':
          _beginClose();
          _closing = true;
          if (!_closed.isCompleted) _closed.complete();
          if (!_ready.isCompleted) {
            _ready.completeError(
              StateError('Native window closed before startup'),
            );
          }
        case 'error':
          _trace?._acknowledged(event.data);
          _fail(
            StateError(event.data['message'] as String),
            StackTrace.current,
          );
          return;
      }
      _trace?._acknowledged(event.data);
      _events.add(event);
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _bindings.freeEvent(bytes, length);
    }
  }

  Future<void> _finish(Future<dynamic> nativeDone, ReceivePort result) async {
    try {
      final status = await nativeDone;
      _trace?._point(
        'dart.runner_result',
        'close',
        0,
        status: status is int ? status : -1,
      );
      if (status is! int) {
        if (!_ready.isCompleted) {
          _ready.completeError(StateError('Native runner failed: $status'));
        }
        throw StateError('Native runner failed: $status');
      }
      await _closed.future.timeout(
        shutdownTimeout,
        onTimeout: () {
          throw StateError('Native runner exited without a closed event');
        },
      );
      if (status != 0) throw StateError('Native UI loop failed: $status');
    } catch (error, stack) {
      _recordFailure(error, stack);
    } finally {
      _closing = true;
      _shutdownDeadline?.cancel();
      _settlePending(
        _failure ?? StateError('Host closed before acknowledgement'),
        _failureStack,
      );
      for (final dataset in _datasets.values) {
        dataset._owner = null;
      }
      _datasets.clear();
      result.close();
      _trace?._finish();
      _bindings.destroy(_handle);
      _callback.close();
      // A paused event subscriber must not keep native shutdown pending.
      unawaited(_events.close());
      if (!_done.isCompleted) {
        if (_failure case final failure?) {
          _done.completeError(failure, _failureStack);
        } else {
          _done.complete();
        }
      }
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
