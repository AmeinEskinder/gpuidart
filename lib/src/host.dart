import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'nodes.dart';

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
  @override
  String toString() => jsonEncode(data);
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
  late final NativeCallable<_EventNative> _callback;
  late final Pointer<Void> _handle;
  late final Future<void> done;
  int _revision = 1;
  bool _closing = false;

  Stream<GpuiEvent> get events => _events.stream;

  static Future<GpuiHost> open(UiNode root, {String? libraryPath}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'The initial native host currently supports Windows.',
      );
    }
    final path = File(
      libraryPath ??
          Platform.environment['GPUIDART_LIBRARY'] ??
          'target/debug/gpuidart.dll',
    ).absolute.path;
    final host = GpuiHost._(_Bindings(path));
    host._callback = NativeCallable<_EventNative>.listener(host._receive);
    host._handle = host._withSnapshot(
      root,
      (bytes, length) =>
          host._bindings.create(bytes, length, host._callback.nativeFunction),
    );
    if (host._handle == nullptr) {
      host._callback.close();
      await host._events.close();
      throw ArgumentError(
        'Invalid initial UI description. Check IDs and table row widths.',
      );
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

  T _withSnapshot<T>(UiNode root, T Function(Pointer<Uint8>, int) action) {
    final data = utf8.encode(
      jsonEncode({'revision': _revision, 'root': root.toJson()}),
    );
    final bytes = calloc<Uint8>(data.length);
    try {
      bytes.asTypedList(data.length).setAll(0, data);
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
    try {
      final status = _withSnapshot(
        root,
        (bytes, length) => _bindings.publish(_handle, bytes, length),
      );
      if (status != 0) {
        throw StateError('Native snapshot submission failed: $status');
      }
    } catch (_) {
      _pending.remove(revision);
      rethrow;
    }
    return accepted.future;
  }

  Future<void> close() {
    if (!_closing && !_closed.isCompleted) {
      _closing = true;
      _bindings.close(_handle);
    }
    return done;
  }

  void _receive(Pointer<Uint8> bytes, int length) {
    try {
      final event = GpuiEvent._(
        jsonDecode(utf8.decode(bytes.asTypedList(length)))
            as Map<String, dynamic>,
      );
      switch (event.type) {
        case 'ready':
          if (!_ready.isCompleted) _ready.complete();
        case 'applied':
          _pending.remove(event.revision)?.complete();
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
