import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'actions.dart';
import 'theme.dart';
import 'menus.dart';
import 'format.dart';
import 'nodes.dart';
import 'input_state.dart';
import 'metrics.dart';
import 'window_options.dart';
import 'windows.dart';
import 'platform.dart';
import 'trace_clock.dart';
import 'tree_diff.dart';
import 'native_event.dart';

part 'dataset.dart';
part 'tracing.dart';
part 'companion.dart';
part 'input_commands.dart';

final _jsonUtf8 = JsonUtf8Encoder();

/// A queued publication: the tree native will hold once it applies.
final class _Publication {
  const _Publication(
    this.described,
    this.actions,
    this.theme,
    this.menus, {
    required this.viaOps,
  });
  final DescribedNode described;
  final List<UiAction> actions;
  final UiTheme? theme;
  final List<UiMenu> menus;
  final bool viaOps;
}

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
typedef _WindowCommandNative = Int32 Function(
  Pointer<Void>,
  Uint32,
  Pointer<Uint8>,
  Size,
);
typedef _WindowCommandDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Uint8>,
  int,
);
typedef _WindowCloseNative = Int32 Function(Pointer<Void>, Uint32);
typedef _WindowCloseDart = int Function(Pointer<Void>, int);

/// Exports that address secondary windows; absent from older libraries.
final class _WindowBindings {
  _WindowBindings(DynamicLibrary library)
    : open = library.lookupFunction<_PublishNative, _PublishDart>(
        'gd_window_open',
      ),
      close = library.lookupFunction<_WindowCloseNative, _WindowCloseDart>(
        'gd_window_close',
      ),
      publish = library
          .lookupFunction<_WindowCommandNative, _WindowCommandDart>(
            'gd_window_publish',
          ),
      update = library.lookupFunction<_WindowCommandNative, _WindowCommandDart>(
        'gd_window_update',
      ),
      dataset = library
          .lookupFunction<_WindowCommandNative, _WindowCommandDart>(
            'gd_window_dataset',
          ),
      diagnostic = library
          .lookupFunction<_WindowCommandNative, _WindowCommandDart>(
            'gd_window_diagnostic',
          ),
      input = library.lookupFunction<_WindowCommandNative, _WindowCommandDart>(
        'gd_window_input',
      );
  final _PublishDart open;
  final _WindowCloseDart close;
  final _WindowCommandDart publish;
  final _WindowCommandDart update;
  final _WindowCommandDart dataset;
  final _WindowCommandDart diagnostic;
  final _WindowCommandDart input;
}

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
        'Rebuild the native library with this SDK.',
      );
    }
    if (version != expected) {
      throw StateError(
        'Incompatible GPUI-Dart library at $path: ABI $version, expected $expected. '
        'Rebuild the native library with this SDK.',
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
  late final input = _inputBinding();

  /// Null when the library predates operation updates; publishes then send
  /// whole descriptions.
  late final _PublishDart? update = _updateBinding();
  _PublishDart? _updateBinding() {
    try {
      return library.lookupFunction<_PublishNative, _PublishDart>('gd_update');
    } on ArgumentError {
      return null;
    }
  }

  /// Null when the library predates secondary windows.
  late final _WindowBindings? windows = _windowBindings();
  _WindowBindings? _windowBindings() {
    try {
      return _WindowBindings(library);
    } on ArgumentError {
      return null;
    }
  }

  _PublishDart _inputBinding() {
    try {
      return library.lookupFunction<_PublishNative, _PublishDart>('gd_input');
    } on ArgumentError {
      throw StateError(
        'Native library does not support controlled inputs; rebuild it with this SDK',
      );
    }
  }

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

  /// The window this event belongs to: 0 for the main window, otherwise the
  /// ID of the [GpuiWindow] it came from.
  int get window => (data['window'] as int?) ?? 0;
  int? get revision => data['revision'] as int?;
  String? get value => data['value'] as String?;

  /// Requested checkbox state, only present on `checkbox_change` events.
  bool? get checked => data['checked'] as bool?;

  /// Requested slider value, only present on `slider_change` events.
  double? get number => (data['number'] as num?)?.toDouble();

  /// Requested option ID on `select_change` or `tab_change` / `radio_change`; null means no selection.
  String? get selected => data['selected'] as String?;

  /// Requested `YYYY-MM-DD` date on `date_change`; null means cleared.
  String? get date => data['date'] as String?;

  /// The tree item a `tree_select` or `tree_expand` event names.
  String? get item => data['item'] as String?;

  /// Whether a `tree_expand` event opened its folder.
  bool? get expanded => data['expanded'] as bool?;

  /// The new open state a `popover_change` event reports.
  bool? get open => data['open'] as bool?;

  /// Every pane's size in logical pixels on `panes_resize`.
  List<double>? get sizes => type == 'panes_resize'
      ? [for (final size in data['sizes'] as List) (size as num).toDouble()]
      : null;

  /// Whether the user confirmed a `dialog_result`; false means cancelled.
  bool? get confirmed => data['confirmed'] as bool?;

  /// Value/selection/composition state accompanying a controlled native edit.
  UiInputState? get inputState => data['input_state'] == null
      ? null
      : decodeInputState(id!, data['input_state']);

  /// Native row selection, including the dataset revision used for the index.
  TableSelection? get tableSelection => type == 'table_selection'
      ? TableSelection._(
          data['id'] as String,
          data['dataset'] as String,
          data['dataset_revision'] as int,
          data['row'] as int?,
          data['record'] as String?,
        )
      : null;

  /// The table whose view index landed, on a `table_view` event.
  TableViewSettled? get tableView => type == 'table_view'
      ? TableViewSettled._(
          data['id'] as String,
          data['dataset'] as String,
          data['dataset_revision'] as int,
          data['view_rows'] as int,
          data['groups'] as int,
          data['compute_us'] as int,
        )
      : null;

  /// The record a `list_select` event chose, with its dataset revision.
  TableSelection? get listSelection => type == 'list_select'
      ? TableSelection._(
          data['id'] as String,
          data['dataset'] as String,
          data['dataset_revision'] as int,
          data['row'] as int,
          data['record'] as String,
        )
      : null;

  /// A context-menu action bound to a stable dataset record.
  RowActionEvent? get rowAction => type == 'row_action'
      ? RowActionEvent._(
          data['id'] as String,
          data['dataset'] as String,
          data['dataset_revision'] as int,
          data['record'] as String,
          data['action'] as String,
        )
      : null;

  /// A matched action binding. Native never executes commands; the
  /// application decides what [ActionEvent.name] means.
  ActionEvent? get action => type == 'action'
      ? ActionEvent._(
          data['revision'] as int?,
          data['name'] as String,
          data['context'] as String,
        )
      : null;
  @override
  String toString() => jsonEncode(data);
}

final class RowActionEvent {
  const RowActionEvent._(
    this.table,
    this.dataset,
    this.datasetRevision,
    this.record,
    this.action,
  );
  final String table;
  final String dataset;
  final int datasetRevision;
  final String record;
  final String action;
}

/// A matched key binding from the snapshot's `actions` list.
final class ActionEvent {
  const ActionEvent._(this.revision, this.name, this.context);
  final int? revision;
  final String name;

  /// The context that matched: the winning node ID or `global`.
  final String context;
}

/// A row index is meaningful only within [datasetRevision]. Null means cleared.
final class TableSelection {
  const TableSelection._(
    this.table,
    this.dataset,
    this.datasetRevision,
    this.row,
    this.record,
  );
  final String table;
  final String dataset;
  final int datasetRevision;

  /// The view row index; for debugging. Consumers key on [record].
  final int? row;

  /// The selected record's stable ID, when the dataset has record IDs. Null
  /// when it has none or the selection cleared (the disappearance rule emits
  /// a selection with both [row] and [record] null).
  final String? record;
}

/// Experimental desktop host. The Dart application isolate keeps its event loop.
/// A dedicated isolate blocks in the native host. On macOS the host connects to
/// a companion process whose main thread owns the GPUI loop.
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
  final _diagnostics = <int, Completer<Map<String, dynamic>>>{};
  final _inputPending =
      <
        int,
        ({String id, String expected, Completer<UiInputState> completion})
      >{};
  final _datasets = <String, TableDataset>{};
  List<UiAction> _viewActions = const [];
  final _dataPending =
      <int, ({String id, int revision, Completer<void> completion})>{};
  final _dataTimers = <int, Stopwatch>{};
  final metrics = HostMetrics();
  UiNode Function()? _builder;
  UiTheme Function()? _themeBuilder;
  List<UiMenu> Function()? _menusBuilder;
  int _request = 0;
  late final NativeCallable<_EventNative> _callback;
  late final Pointer<Void> _handle;
  final _done = Completer<void>();
  Future<void> get done => _done.future;
  Timer? _shutdownDeadline;
  Object? _failure;
  StackTrace? _failureStack;

  /// Publication state of the main window; secondary windows carry their own.
  late final _View _main = _View(this, 0);
  final _windows = <int, GpuiWindow>{};
  final _windowPending =
      <int, ({GpuiWindow window, Completer<void> completion})>{};
  int _windowIds = 0;
  bool _closing = false;
  _Companion? _companion;

  Stream<GpuiEvent> get events => _events.stream;

  /// Tracks every execution of the application's description builder.
  static Future<GpuiHost> openView(
    UiNode Function() builder, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    List<UiAction> actions = const [],
    UiTheme Function()? theme,
    List<UiMenu> Function()? menus,
    GpuiWindowOptions window = const GpuiWindowOptions(),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 10),
    GpuiTrace? trace,
    bool deferDatasets = false,
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
      actions: actions,
      theme: theme?.call(),
      menus: menus?.call() ?? const [],
      window: window,
      requestTimeout: requestTimeout,
      shutdownTimeout: shutdownTimeout,
      trace: trace,
      deferDatasets: deferDatasets,
    );
    host._builder = builder;
    host._themeBuilder = theme;
    host._menusBuilder = menus;
    host._viewActions = List.unmodifiable(actions);
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
        : _trace._measure(
            'dart.build',
            'snapshot',
            _main.revision + 1,
            builder,
          );
    HostMetrics.sample(metrics.buildMicroseconds, timer.elapsedMicroseconds);
    return publish(
      root,
      actions: _viewActions,
      theme: _themeBuilder?.call(),
      menus: _menusBuilder?.call() ?? const [],
    );
  }

  static Future<GpuiHost> open(
    UiNode root, {
    String? libraryPath,
    List<TableDataset> datasets = const [],
    List<UiAction> actions = const [],
    UiTheme? theme,
    List<UiMenu> menus = const [],
    GpuiWindowOptions window = const GpuiWindowOptions(),
    Duration requestTimeout = const Duration(seconds: 30),
    Duration shutdownTimeout = const Duration(seconds: 10),
    GpuiTrace? trace,
    bool deferDatasets = false,
  }) async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError(
        'This host supports Windows, macOS and Linux X11.',
      );
    }
    if (requestTimeout <= Duration.zero || shutdownTimeout <= Duration.zero) {
      throw ArgumentError('Host deadlines must be positive');
    }
    final windowDescription = window.toJson();
    trace?._claim();
    trace?._point('dart.request', 'initial', 1);
    if (Platform.isWindows) configureWindowsDpi();
    final path = resolveNativeLibrary(libraryPath);
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
    final described = DescribedNode.describe(root);
    final plans = {
      for (final dataset in datasets) dataset.id: dataset._chunks(),
    };
    final initial = <String, Object>{
      'snapshot': {
        'revision': 1,
        'root': described.json,
        if (theme != null) 'theme': theme.toJson(),
        if (menus.isNotEmpty) 'menus': encodeMenus(menus),
        if (actions.isNotEmpty)
          'actions': actions.map((action) => action.toJson()).toList(),
      },
      'datasets': [
        for (final dataset in datasets)
          deferDatasets || plans[dataset.id]!.length > 1
              ? dataset._uploadSchema()
              : dataset._upload(),
      ],
      'window': windowDescription,
    };
    if (describeStart != null) {
      trace!._span('dart.describe', 'initial', 1, describeStart);
    }
    host._callback = NativeCallable<_EventNative>.listener(host._receive);
    Pointer<Void> created = nullptr;
    try {
      created = host._handle = host._withMessage(initial, 'initial', 1, (
        bytes,
        length,
      ) {
        if (nativeTrace?.create case final tracedCreate?) {
          return tracedCreate(
            bytes,
            length,
            host._callback.nativeFunction,
            trace!.capacity,
          );
        }
        return host._bindings.create(
          bytes,
          length,
          host._callback.nativeFunction,
        );
      });
      if (host._handle == nullptr) {
        throw ArgumentError(
          'Native host creation rejected. Check node IDs and dataset schema; '
          'only one GPUI host may be active in a process.',
        );
      }
      if (nativeTrace != null) {
        if (nativeTrace.create == null &&
            nativeTrace.enable(host._handle, trace!.capacity) != 0) {
          throw StateError('Native trace enable failed');
        }
        trace!._attach(() => nativeTrace.snapshot(bindings, host._handle));
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
    host._main.baseline = described;
    host._main.baselineRevision = 1;
    final result = ReceivePort();
    final nativeDone = result.first;
    try {
      final companionStart = trace?._clock.now();
      host._companion = await _Companion.start(bindings, path, host._handle);
      if (companionStart != null && host._companion != null) {
        trace!._span('dart.companion_start', 'initial', 1, companionStart);
      }
      final runnerStart = trace?._clock.now();
      await Isolate.spawn(
        _runNative,
        (path, host._handle.address, result.sendPort, host._companion != null),
        onError: result.sendPort,
        onExit: result.sendPort,
        errorsAreFatal: true,
        debugName: 'gpui-native-loop',
      );
      if (runnerStart != null) {
        trace!._span('dart.runner_spawn', 'initial', 1, runnerStart);
      }
    } catch (_) {
      await host._companion?.abortStartup();
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
      // Deferred records follow as ordinary replacements, and records too
      // large for one message as appended slices behind their schema; either
      // way the first frame never waits for them.
      await Future.wait([
        for (final dataset in datasets)
          host._uploadRecords(
            dataset,
            plans[dataset.id]!,
            deferred: deferDatasets,
          ),
      ]);
    } catch (_) {
      // A rejected or unpackable upload is a failed open: the window closes
      // and the error reaches the caller.
      host._beginClose();
      await host.done.catchError((Object _) {});
      rethrow;
    }
    return host;
  }

  T _withMessage<T>(
    Map<String, Object> message,
    String kind,
    int request,
    T Function(Pointer<Uint8>, int) action, {
    bool traced = true,
    Uint8List? attachment,
  }) {
    final trace = traced ? _trace : null;
    final timer = Stopwatch()..start();
    final encodingStart = trace?._clock.now();
    List<int> data;
    // Internal comparison control; the default build removes this legacy path.
    if (const bool.fromEnvironment('gpuidart.legacy_json')) {
      final json = trace == null
          ? jsonEncode(message)
          : trace._measure(
              'dart.json',
              kind,
              request,
              () => jsonEncode(message),
            );
      data = trace == null
          ? utf8.encode(json)
          : trace._measure('dart.utf8', kind, request, () => utf8.encode(json));
    } else {
      data = trace == null
          ? _jsonUtf8.convert(message)
          : trace._measure(
              'dart.json_utf8',
              kind,
              request,
              () => _jsonUtf8.convert(message),
            );
    }
    if (attachment != null) {
      // A framed message: magic, header length, JSON header, packed records.
      final framed = Uint8List(8 + data.length + attachment.length);
      framed.setRange(0, 4, const [0x47, 0x44, 0x50, 0x31]);
      ByteData.sublistView(framed).setUint32(4, data.length, Endian.little);
      framed.setRange(8, 8 + data.length, data);
      framed.setRange(8 + data.length, framed.length, attachment);
      data = framed;
    }
    final copyStart = trace?._clock.now();
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
      if (copyStart != null) {
        trace!._span(
          'dart.ffi_copy',
          kind,
          request,
          copyStart,
          bytes: data.length,
        );
      }
      metrics.recordEncoding(kind, data.length, timer.elapsedMicroseconds);
      if (encodingStart != null) {
        trace!._span(
          'dart.encode',
          kind,
          request,
          encodingStart,
          bytes: data.length,
        );
      }
      final ffiStart = trace?._clock.now();
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
          trace!._span(
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
  ///
  /// The host sends the operations that turn the previously published tree
  /// into [root] when it can, and the whole description otherwise: after a
  /// failed publication, when the root changes identity or a node changes
  /// kind under the same ID, or with a native library that predates updates.
  /// Either way native applies the result atomically at [root]'s revision.
  ///
  /// Actions are declared per snapshot like the node tree: [actions] replaces
  /// the bindings, and omitting it clears them. [openView] rebuilds redeclare
  /// the actions passed to [openView].
  Future<void> publish(
    UiNode root, {
    List<UiAction> actions = const [],
    UiTheme? theme,
    List<UiMenu> menus = const [],
  }) => _main.publish(root, actions: actions, theme: theme, menus: menus);

  /// Writes one published node's own fields without a rebuild: [node] must
  /// keep the ID and kind of a node in the last publication and carry no
  /// children. Native applies it as one `set` operation, so a bound value
  /// costs neither build, describe nor diff. The write stands until the next
  /// publication, which carries the application's value for that node.
  Future<void> patch(UiNode node) => _main.patch(node);

  /// Completes once every table view in the main window has its index.
  ///
  /// A view over 10,000 records or more computes off the frame thread: the
  /// publication or edit that changes it is acknowledged at once, the table
  /// shows its last rows meanwhile, and a `table_view` event follows when
  /// the index lands. Edits to that dataset sent in between apply, and are
  /// acknowledged, after it. Smaller views compute in place and this
  /// completes immediately. Anything that inspects a table after a
  /// publication or edit awaits this first; the future completes after the
  /// last `table_view` event has reached [events] listeners.
  Future<void> get viewsSettled => _main.viewsSettled;

  /// Opens a secondary window with its own description and datasets. See
  /// docs/windows.md. Completes once native has opened the window; a
  /// rejected request throws a [StateError].
  Future<GpuiWindow> openWindow(
    UiNode root, {
    GpuiWindowOptions options = const GpuiWindowOptions(),
    List<TableDataset> datasets = const [],
    List<UiAction> actions = const [],
  }) async {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final windows = _bindings.windows;
    if (windows == null) {
      throw StateError(
        'Native library does not support secondary windows; rebuild it with this SDK',
      );
    }
    final description = options.toJson();
    final ids = <String>{};
    for (final dataset in datasets) {
      if (dataset._owner != null ||
          dataset._busy ||
          _datasets.containsKey(dataset.id) ||
          !ids.add(dataset.id)) {
        throw ArgumentError(
          'Dataset is already registered or its ID is duplicated',
        );
      }
    }
    final id = ++_windowIds;
    final request = ++_request;
    final described = DescribedNode.describe(root);
    final window = GpuiWindow._(this, id);
    final completion = Completer<void>();
    final status = _withMessage(
      {
        'request': request,
        'id': id,
        'initial': {
          'snapshot': {
            'revision': 1,
            'root': described.json,
            if (actions.isNotEmpty)
              'actions': actions.map((action) => action.toJson()).toList(),
          },
          'datasets': datasets.map((dataset) => dataset._upload()).toList(),
          'window': description,
        },
      },
      'window',
      request,
      (bytes, length) => windows.open(_handle, bytes, length),
      traced: false,
    );
    if (status != 0) {
      final error = StateError('Window request failed: $status');
      if (status == -4) _fail(error, StackTrace.current);
      throw error;
    }
    window._view.baseline = described;
    window._view.baselineRevision = 1;
    for (final dataset in datasets) {
      dataset._owner = this;
      dataset._window = id;
      dataset._revision = 1;
      _datasets[dataset.id] = dataset;
    }
    _windows[id] = window;
    _windowPending[request] = (window: window, completion: completion);
    try {
      await _withDeadline(completion.future, 'window $request');
    } catch (error, stack) {
      _windows.remove(id);
      window._settle(error, stack);
      rethrow;
    }
    return window;
  }

  _View? _viewFor(GpuiEvent event) =>
      event.window == 0 ? _main : _windows[event.window]?._view;

  Future<void> registerDataset(TableDataset dataset) =>
      _register(dataset, window: 0);

  Future<void> editDataset(TableDataset dataset, List<TableEdit> edits) {
    final batch = List<TableEdit>.of(edits);
    if (batch.isEmpty) {
      throw ArgumentError('Dataset edit batch must be nonempty');
    }
    final shape = _DatasetShape(dataset);
    for (final edit in batch) {
      edit._validate(shape);
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

  /// Replaces rows, record IDs and cell formats together; `Edit` batches
  /// never change identity or formats.
  Future<void> replaceDataset(
    TableDataset dataset, {
    required List<String> columns,
    required List<List<String>> rows,
    List<String>? rowIds,
    Map<int, UiColumnFormat>? formats,
  }) async {
    final replacement = TableDataset(
      dataset.id,
      columns: columns,
      rows: rows,
      rowIds: rowIds,
      formats: formats,
    );
    // The Dart records follow each acknowledgement, so between the slices of
    // a large replacement they match what native holds.
    final chunks = replacement._chunks();
    final first = chunks.first.$2;
    await _transact(
      dataset,
      {'op': 'replace', 'data': replacement._dataRange(0, first)},
      () {
        dataset._columns = replacement._columns;
        dataset._identity = replacement._identity;
        dataset._formats = replacement._formats;
        dataset._rowCount = first;
        if (dataset.retainRecords) {
          dataset._rows = replacement._rows.sublist(0, first);
          dataset._rowIds = replacement._rowIds?.sublist(0, first);
        }
      },
    );
    if (chunks.length > 1) {
      await _appendSlices(dataset, replacement, chunks, 1, (start, end) {
        dataset._rowCount += end - start;
        if (dataset.retainRecords) {
          dataset._rows.addAll(replacement._rows.sublist(start, end));
          dataset._rowIds?.addAll(replacement._rowIds!.sublist(start, end));
        }
      });
    }
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
      _companion?.armDeadline();
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
    _main.settle(error, stack);
    for (final window in _windows.values.toList()) {
      window._settle(error, stack);
    }
    _windows.clear();
    for (final pending in _windowPending.values) {
      pending.completion.completeError(error, stack);
    }
    _windowPending.clear();
    for (final pending in _dataPending.values) {
      pending.completion.completeError(error, stack);
    }
    _dataPending.clear();
    _dataTimers.clear();
    for (final pending in _diagnostics.values) {
      pending.completeError(error, stack);
    }
    _diagnostics.clear();
    for (final pending in _inputPending.values) {
      pending.completion.completeError(error, stack);
    }
    _inputPending.clear();
  }

  /// Opt-in native inspection and test control; no commands run during repaint.
  /// Opens the native file or folder chooser. Resolves to the chosen paths,
  /// or null when the user cancelled, once the dialog closes.
  Future<List<String>?> pickPaths({
    bool files = true,
    bool directories = false,
    bool multiple = false,
    String? prompt,
  }) async {
    final reply = await diagnose('prompt_paths', {
      'files': files,
      'directories': directories,
      'multiple': multiple,
      'prompt': ?prompt,
    });
    _checkReply(reply);
    return (reply['paths'] as List?)?.cast<String>();
  }

  /// Opens the native save dialog in [directory]. Resolves to the chosen
  /// path, or null when the user cancelled.
  Future<String?> pickSavePath(
    String directory, {
    String? suggestedName,
  }) async {
    final reply = await diagnose('prompt_save_path', {
      'directory': directory,
      'suggested_name': ?suggestedName,
    });
    _checkReply(reply);
    return reply['path'] as String?;
  }

  /// Opens an http, https or mailto URL with the operating system's handler.
  Future<void> openUrl(String url) async =>
      _checkReply(await diagnose('open_url', {'url': url}));

  /// Shows [path] in the operating system's file manager.
  Future<void> revealPath(String path) async =>
      _checkReply(await diagnose('reveal_path', {'path': path}));

  static void _checkReply(Map<String, dynamic> reply) {
    if (reply['error'] case final String error) throw StateError(error);
  }

  Future<Map<String, dynamic>> diagnose(
    String op, [
    Map<String, Object> arguments = const {},
  ]) => _diagnose(0, op, arguments);

  Future<Map<String, dynamic>> _diagnose(
    int window,
    String op,
    Map<String, Object> arguments,
  ) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    final request = ++_request;
    if (window == 0) _trace?._point('dart.request', 'diagnostic', request);
    final completion = Completer<Map<String, dynamic>>();
    final status = _withMessage(
      {...arguments, 'op': op, 'request': request},
      'diagnostic',
      request,
      (bytes, length) => window == 0
          ? _bindings.diagnostic(_handle, bytes, length)
          : _bindings.windows!.diagnostic(_handle, window, bytes, length),
      traced: window == 0,
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
          event.type == 'action' ||
          event.type == 'table_selection' ||
          event.type == 'row_action' ||
          event.type == 'checkbox_change' ||
          event.type == 'slider_change' ||
          event.type == 'select_change' ||
          event.type == 'date_change' ||
          event.type == 'panes_resize' ||
          event.type == 'tree_select' ||
          event.type == 'tree_expand' ||
          event.type == 'popover_change' ||
          event.type == 'sheet_close' ||
          event.type == 'switch_change' ||
          event.type == 'radio_change' ||
          event.type == 'tab_change' ||
          event.type == 'list_select' ||
          event.type == 'dialog_result') {
        metrics.uiCallbacks++;
      }
      if (event.type == 'diagnostic') metrics.diagnosticCallbacks++;
      switch (event.type) {
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'applied':
          _viewFor(event)?.applied(event);
        case 'rejected':
          _viewFor(event)?.rejected(event);
        case 'window_opened':
          _windowPending.remove(event.data['request'])?.completion.complete();
        case 'window_rejected':
          _windowPending
              .remove(event.data['request'])
              ?.completion
              .completeError(StateError(event.data['message'] as String));
        case 'window_closed':
          _windows.remove(event.window)?._closed();
        case 'dataset_applied':
          _viewFor(event)?.syncPendingViews(event);
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
        case 'input_result':
          final pending = _inputPending[event.data['request']];
          if (pending != null) {
            if (pending.id != event.id) {
              throw const FormatException('Input acknowledgement ID mismatch');
            }
            final status = event.data['status'];
            if ((status == 'read' || status == 'applied') &&
                status != pending.expected) {
              throw const FormatException(
                'Input acknowledgement operation mismatch',
              );
            }
            final state = event.data['state'] == null
                ? null
                : decodeInputState(event.id!, event.data['state']);
            _inputPending.remove(event.data['request']);
            if (event.data['status'] == 'read' ||
                event.data['status'] == 'applied') {
              pending.completion.complete(state!);
            } else {
              pending.completion.completeError(
                InputWriteException(event.data['status'] as String, state),
              );
            }
          }
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
          if (event.window == 0) _trace?._acknowledged(event.data);
          _fail(
            StateError(event.data['message'] as String),
            StackTrace.current,
          );
          return;
      }
      if (event.window == 0) _trace?._acknowledged(event.data);
      _events.add(event);
      // After the event is on the stream, so a listener sees the landed view
      // before an awaiter of viewsSettled resumes.
      if (event.type == 'table_view') _viewFor(event)?.viewSettled(event.id!);
    } catch (error, stack) {
      _fail(error, stack);
    } finally {
      _bindings.freeEvent(bytes, length);
    }
  }

  Future<void> _finish(Future<dynamic> nativeDone, ReceivePort result) async {
    try {
      final status = await nativeDone;
      final companionStatus = await _companion?.finish();
      if (companionStatus != null && companionStatus != 0) {
        throw StateError('Native companion exited with code $companionStatus');
      }
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

void _runNative((String, int, SendPort, bool) args) {
  try {
    final bindings = _Bindings(args.$1);
    final handle = Pointer<Void>.fromAddress(args.$2);
    if (args.$4) {
      final run = bindings.library.lookupFunction<_RunNative, _RunDart>(
        'gd_run_companion',
      );
      args.$3.send(run(handle));
    } else {
      args.$3.send(bindings.run(handle));
    }
  } catch (error, stack) {
    args.$3.send('$error\n$stack');
  }
}

/// Publication state for one window: the main window (0) or a secondary one.
/// Revisions, the queued baseline and in-flight publications are per window.
final class _View {
  _View(this.host, this.window);
  final GpuiHost host;
  final int window;
  int revision = 1;

  /// The description native will hold once every queued publication applies,
  /// and its revision. Null after any failure, so the next publication sends
  /// the whole description again.
  DescribedNode? baseline;
  int baselineRevision = 0;

  /// Queued publications native has not acknowledged, by revision. A stale
  /// rejection resubmits the latest of them as a whole description.
  final inFlight = <int, _Publication>{};
  final pending = <int, Completer<void>>{};
  final publishTimers = <int, Stopwatch>{};

  /// Tables whose view index is computing off the frame thread, as the last
  /// acknowledgement listed them; each `table_view` event retires one.
  final pendingViews = <String>{};
  Completer<void>? _viewsSettled;

  Future<void> get viewsSettled {
    if (pendingViews.isEmpty) return Future.value();
    return (_viewsSettled ??= Completer<void>()).future;
  }

  void syncPendingViews(GpuiEvent event) {
    final listed = event.data['pending_views'];
    pendingViews
      ..clear()
      ..addAll(listed is List ? listed.cast<String>() : const []);
    _settleViews();
  }

  void viewSettled(String table) {
    pendingViews.remove(table);
    _settleViews();
  }

  void _settleViews() {
    if (pendingViews.isNotEmpty) return;
    _viewsSettled?.complete();
    _viewsSettled = null;
  }

  /// Snapshot-level fields of the last submission; an operation update
  /// restates them, and omitting them would clear them.
  List<UiAction> actions = const [];
  UiTheme? theme;
  List<UiMenu> menus = const [];

  /// Tracing covers the main window only.
  GpuiTrace? get trace => window == 0 ? host._trace : null;

  Future<void> publish(
    UiNode root, {
    List<UiAction> actions = const [],
    UiTheme? theme,
    List<UiMenu> menus = const [],
  }) {
    if (host._closing || host._closed.isCompleted) {
      throw StateError('Host is closing');
    }
    final revision = ++this.revision;
    trace?._point('dart.request', 'snapshot', revision);
    final accepted = Completer<void>();
    pending[revision] = accepted;
    publishTimers[revision] = Stopwatch()..start();
    var status = 0;
    try {
      final baseline = this.baseline;
      final described = trace == null
          ? DescribedNode.describe(root, previous: baseline)
          : trace!._measure(
              'dart.describe',
              'snapshot',
              revision,
              () => DescribedNode.describe(root, previous: baseline),
            );
      final canUpdate = window != 0 || host._bindings.update != null;
      // A binding context absent from the tree is a submission error for a
      // whole description; keep that synchronous contract for operations too.
      final contextsPresent =
          actions.isEmpty ||
          () {
            final ids = described.ids();
            return actions.every(
              (action) => switch (action.context) {
                UiGlobalActionContext() => true,
                UiNodeActionContext(:final id) => ids.contains(id),
              },
            );
          }();
      final ops = baseline == null || !canUpdate || !contextsPresent
          ? null
          : trace == null
          ? diffDescribed(baseline, described)
          : trace!._measure(
              'dart.diff',
              'snapshot',
              revision,
              () => diffDescribed(baseline, described),
            );
      described.seal();
      this.baseline = null;
      status = _submitDescription(
        revision,
        described,
        actions,
        theme,
        menus,
        ops: ops,
      );
      if (status != 0) {
        throw StateError('Native snapshot submission failed: $status');
      }
      if (ops != null) host.metrics.operationPublications++;
    } catch (error, stack) {
      pending.remove(revision);
      publishTimers.remove(revision);
      if (status == -4) host._fail(error, stack);
      rethrow;
    }
    return host._withDeadline(accepted.future, 'snapshot $revision');
  }

  /// Sends [described] at [revision], as [ops] against the queued baseline or
  /// as the whole description, and records it as queued on success.
  int _submitDescription(
    int revision,
    DescribedNode described,
    List<UiAction> actions,
    UiTheme? theme,
    List<UiMenu> menus, {
    required List<Map<String, Object?>>? ops,
  }) {
    final bindings = host._bindings;
    final handle = host._handle;
    final status = host._withMessage(
      {
        'revision': revision,
        if (ops == null) 'root': described.json,
        if (ops != null) 'base_revision': baselineRevision,
        'ops': ?ops,
        if (actions.isNotEmpty)
          'actions': actions.map((action) => action.toJson()).toList(),
        if (theme != null) 'theme': theme.toJson(),
        if (menus.isNotEmpty) 'menus': encodeMenus(menus),
      },
      'snapshot',
      revision,
      (bytes, length) => switch ((window, ops)) {
        (0, null) => bindings.publish(handle, bytes, length),
        (0, _) => bindings.update!(handle, bytes, length),
        (_, null) => bindings.windows!.publish(handle, window, bytes, length),
        _ => bindings.windows!.update(handle, window, bytes, length),
      },
      traced: window == 0,
    );
    if (status == 0) {
      baseline = described;
      baselineRevision = revision;
      this.actions = actions;
      this.theme = theme;
      this.menus = menus;
      inFlight[revision] = _Publication(
        described,
        actions,
        theme,
        menus,
        viaOps: ops != null,
      );
    }
    return status;
  }

  Future<void> patch(UiNode node) {
    if (host._closing || host._closed.isCompleted) {
      throw StateError('Host is closing');
    }
    final baseline = this.baseline;
    final canUpdate = window != 0 || host._bindings.update != null;
    if (baseline == null || !canUpdate) {
      throw StateError(
        'A patch builds on an accepted publication; publish the tree first',
      );
    }
    if (node.children.isNotEmpty) {
      throw ArgumentError.value(node.id, 'node', 'A patch carries no children');
    }
    final target = baseline.find(node.id);
    if (target == null) {
      throw ArgumentError.value(node.id, 'node', 'Not in the published tree');
    }
    final fields = node.props();
    if (fields['kind'] != target.kind) {
      throw ArgumentError.value(node.id, 'node', 'A patch keeps the node kind');
    }
    final revision = ++this.revision;
    trace?._point('dart.request', 'snapshot', revision);
    final accepted = Completer<void>();
    pending[revision] = accepted;
    publishTimers[revision] = Stopwatch()..start();
    // The baseline shows the value from now on, so a later diff or a whole
    // resubmission carries it.
    final previous = Map<String, Object>.of(target.json);
    final previousSource = target.source;
    target.patch(fields);
    var status = 0;
    try {
      status = _submitDescription(
        revision,
        baseline,
        actions,
        theme,
        menus,
        ops: [
          {'op': 'set', 'id': node.id, 'node': fields},
        ],
      );
      if (status != 0) {
        throw StateError('Native patch submission failed: $status');
      }
      host.metrics.patches++;
    } catch (error, stack) {
      target.patch(previous);
      target.source = previousSource;
      pending.remove(revision);
      publishTimers.remove(revision);
      if (status == -4) host._fail(error, stack);
      rethrow;
    }
    return host._withDeadline(accepted.future, 'patch $revision');
  }

  /// Native rejected [rejected] because its base was never applied. Every
  /// queued publication from it onwards was computed against that missing
  /// state, and each carries the whole intended tree, so the latest one is
  /// resent as a whole description and completes all of them.
  void _resubmitLatest(int rejected, _Publication flight) {
    final superseded = inFlight.keys.where((r) => r > rejected).toList()
      ..sort();
    final latest = superseded.isEmpty ? flight : inFlight[superseded.last]!;
    final completers = <Completer<void>>[
      ?pending.remove(rejected),
      for (final revision in superseded) ?pending.remove(revision),
    ];
    publishTimers.remove(rejected);
    for (final revision in superseded) {
      inFlight.remove(revision);
      publishTimers.remove(revision);
    }
    final revision = ++this.revision;
    trace?._point('dart.request', 'snapshot', revision);
    final merged = Completer<void>();
    pending[revision] = merged;
    publishTimers[revision] = Stopwatch()..start();
    merged.future.then(
      (_) {
        for (final completer in completers) {
          completer.complete();
        }
      },
      onError: (Object error, StackTrace stack) {
        for (final completer in completers) {
          completer.completeError(error, stack);
        }
      },
    );
    var status = 0;
    try {
      status = _submitDescription(
        revision,
        latest.described,
        latest.actions,
        latest.theme,
        latest.menus,
        ops: null,
      );
      if (status != 0) {
        throw StateError('Native snapshot submission failed: $status');
      }
      host.metrics.resubmittedPublications++;
    } catch (error, stack) {
      pending.remove(revision);
      publishTimers.remove(revision);
      merged.completeError(error, stack);
      if (status == -4) host._fail(error, stack);
    }
  }

  void applied(GpuiEvent event) {
    syncPendingViews(event);
    final timer = publishTimers.remove(event.revision);
    if (timer != null) {
      HostMetrics.sample(
        host.metrics.nativeSnapshotApplyMicroseconds,
        event.data['native_apply_us'] as int,
      );
      HostMetrics.sample(
        host.metrics.applyMicroseconds,
        timer.elapsedMicroseconds,
      );
    }
    inFlight.remove(event.revision);
    pending.remove(event.revision)?.complete();
  }

  void rejected(GpuiEvent event) {
    final flight = inFlight.remove(event.revision);
    final message = event.data['message'] as String;
    if (flight != null &&
        flight.viaOps &&
        message.startsWith('Stale base revision')) {
      _resubmitLatest(event.revision!, flight);
    } else {
      baseline = null;
      publishTimers.remove(event.revision);
      pending.remove(event.revision)?.completeError(StateError(message));
    }
  }

  void settle(Object error, StackTrace? stack) {
    for (final completer in pending.values) {
      completer.completeError(error, stack);
    }
    pending.clear();
    publishTimers.clear();
    inFlight.clear();
    baseline = null;
    pendingViews.clear();
    _viewsSettled?.completeError(error, stack);
    _viewsSettled = null;
  }
}

/// A table's view index landed, from a `table_view` event: the rows and
/// group headers it now shows, over the dataset at [datasetRevision], and
/// how long the index took to compute.
final class TableViewSettled {
  const TableViewSettled._(
    this.table,
    this.dataset,
    this.datasetRevision,
    this.rows,
    this.groups,
    this.computeMicroseconds,
  );
  final String table;
  final String dataset;
  final int datasetRevision;
  final int rows;
  final int groups;
  final int computeMicroseconds;
}

/// A secondary native window opened by [GpuiHost.openWindow]. It publishes
/// its own description, owns the datasets registered through it, and closes
/// independently of the main window. See docs/windows.md.
final class GpuiWindow {
  GpuiWindow._(this._host, this.id) : _view = _View(_host, id) {
    // Callers may never await done; a host failure must not surface as an
    // unhandled error through it.
    unawaited(done.catchError((Object _) {}));
  }
  final GpuiHost _host;

  /// The window ID native addresses; 1 or above. The main window is 0.
  final int id;
  final _View _view;
  final _done = Completer<void>();
  bool _closing = false;

  /// Completes when native reports the window closed, by [close], by the
  /// user or with the application. Completes with an error when the host
  /// fails first.
  Future<void> get done => _done.future;

  /// The host's events from this window.
  Stream<GpuiEvent> get events =>
      _host.events.where((event) => event.window == id);

  void _checkOpen() {
    if (_closing || _done.isCompleted) throw StateError('Window $id is closed');
  }

  /// Publishes to this window with the same rules as [GpuiHost.publish].
  Future<void> publish(
    UiNode root, {
    List<UiAction> actions = const [],
    UiTheme? theme,
    List<UiMenu> menus = const [],
  }) {
    _checkOpen();
    return _view.publish(root, actions: actions, theme: theme, menus: menus);
  }

  /// Writes one published node's own fields in this window; see
  /// [GpuiHost.patch].
  Future<void> patch(UiNode node) {
    _checkOpen();
    return _view.patch(node);
  }

  /// Native inspection addressed to this window; see [GpuiHost.diagnose].
  Future<Map<String, dynamic>> diagnose(
    String op, [
    Map<String, Object> arguments = const {},
  ]) {
    _checkOpen();
    return _host._diagnose(id, op, arguments);
  }

  /// Completes once every table view in this window has its index; see
  /// [GpuiHost.viewsSettled].
  Future<void> get viewsSettled => _view.viewsSettled;

  /// Samples a controlled input in this window; see [InputCommands.readInput].
  Future<UiInputState> readInput(String id) {
    _checkOpen();
    return _host._inputCommand(id, {'op': 'read'}, window: this.id);
  }

  /// Writes a controlled input in this window; see [InputCommands.writeInput].
  Future<UiInputState> writeInput(
    UiInputState base, {
    String? text,
    UiTextSelection? selection,
  }) {
    _checkOpen();
    validateInputWrite(text, selection);
    return _host._inputCommand(base.id, {
      'op': 'write',
      'generation': base.generation,
      'base_revision': base.editRevision,
      'text': ?text,
      'selection': ?selection?.toJson(),
    }, window: id);
  }

  /// Registers a dataset with this window. Later edits, replacements and
  /// release go through the host, which routes them to this window.
  Future<void> registerDataset(TableDataset dataset) {
    _checkOpen();
    return _host._register(dataset, window: id);
  }

  /// Asks native to close the window. Idempotent; returns [done]. Throws when
  /// the request could not be queued, and the window stays open.
  Future<void> close() {
    if (!_closing && !_done.isCompleted) {
      final status = _host._bindings.windows!.close(_host._handle, id);
      if (status != 0) {
        final error = StateError('Window close failed: $status');
        if (status == -4) _host._fail(error, StackTrace.current);
        throw error;
      }
      _closing = true;
    }
    return done;
  }

  /// Native reported the window closed.
  void _closed() => _settle(StateError('Window $id closed'), null);

  /// Ends the window on the Dart side: pending work fails with [error], its
  /// datasets are released and [done] completes, with the host's failure
  /// when there is one.
  void _settle(Object error, StackTrace? stack) {
    _closing = true;
    _release();
    _view.settle(error, stack);
    if (_done.isCompleted) return;
    if (_host._failure case final failure?) {
      _done.completeError(failure, _host._failureStack);
    } else {
      _done.complete();
    }
  }

  void _release() {
    _host._datasets.removeWhere((_, dataset) {
      if (dataset._window != id) return false;
      dataset._owner = null;
      return true;
    });
  }
}
