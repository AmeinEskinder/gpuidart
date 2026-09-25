part of 'host.dart';

/// Bounded, opt-in tracing for one host attempt, using Windows QPC on both sides.
/// Export after [GpuiHost.done] for a finalized capture. No UI values are recorded.
final class GpuiTrace {
  GpuiTrace({this.capacity = 4096}) {
    if (capacity < 1 || capacity > 8192) {
      throw RangeError.range(capacity, 1, 8192, 'capacity');
    }
    if (!Platform.isWindows) throw UnsupportedError('Tracing requires Windows');
    _clock = _TraceClock();
  }

  final int capacity;
  late final _TraceClock _clock;
  final _records = <_TraceRecord>[];
  List<_TraceRecord> _nativeRecords = [];
  int _dropped = 0;
  int _nativeDropped = 0;
  bool _claimed = false;
  bool _nativeAttached = false;
  bool _nativeError = false;
  Map<String, dynamic> Function()? _reader;

  /// Measures synchronous application work. Use a static label without user data.
  T measure<T>(String label, T Function() action) {
    if (label.isEmpty || label.length > 64) {
      throw ArgumentError('Trace labels must contain 1..64 characters');
    }
    return _measure('app.$label', 'application', 0, action);
  }

  T _measure<T>(
    String name,
    String operation,
    int request,
    T Function() action,
  ) {
    final start = _clock.now();
    var status = 0;
    try {
      return action();
    } catch (_) {
      status = -1;
      rethrow;
    } finally {
      _span(name, operation, request, start, status: status);
    }
  }

  void _ensureUnclaimed() {
    if (_claimed) {
      throw StateError('Use a separate trace for each host attempt');
    }
  }

  void _claim() {
    _ensureUnclaimed();
    _claimed = true;
  }

  void _attach(Map<String, dynamic> Function() reader) {
    _reader = reader;
    _nativeAttached = true;
  }

  void _captureNative() {
    final reader = _reader;
    if (reader == null) return;
    try {
      final value = reader();
      final records = value['records'];
      if (value['schema'] != 1 ||
          value['limit'] != capacity ||
          value['dropped'] is! int ||
          (value['dropped'] as int) < 0 ||
          records is! List ||
          records.length > capacity) {
        throw const FormatException('Invalid native trace envelope');
      }
      final decoded = records.map(_TraceRecord.fromNative).toList();
      _nativeRecords = decoded;
      _nativeDropped = value['dropped'] as int;
    } catch (_) {
      // A diagnostic capture must not change application shutdown semantics.
      _nativeError = true;
    }
  }

  void _finish() {
    _captureNative();
    _reader = null;
  }

  void _add(_TraceRecord record) {
    if (_records.length == capacity) {
      _dropped++;
    } else {
      _records.add(record);
    }
  }

  void _point(
    String name,
    String operation,
    int request, {
    (int, int)? at,
    int? bytes,
    int? status,
    int? nativeApplyUs,
  }) {
    final stamp = at ?? _clock.now();
    _add(
      _TraceRecord(
        name,
        operation,
        request,
        stamp.$1,
        stamp.$1,
        stamp.$2,
        bytes: bytes,
        status: status,
        nativeApplyUs: nativeApplyUs,
      ),
    );
  }

  void _span(
    String name,
    String operation,
    int request,
    (int, int) start, {
    int? bytes,
    int? status,
  }) => _add(
    _TraceRecord(
      name,
      operation,
      request,
      start.$1,
      _clock.now().$1,
      start.$2,
      bytes: bytes,
      status: status,
    ),
  );

  (String, int)? _eventKey(Map<String, dynamic> data) => switch (data['type']) {
    'ready' => ('initial', 1),
    'applied' || 'rejected' => ('snapshot', data['revision'] as int),
    'dataset_applied' ||
    'dataset_rejected' => ('dataset', data['request'] as int),
    'diagnostic' => ('diagnostic', data['request'] as int),
    'closed' => ('close', 0),
    'error' => ('failure', 0),
    _ => null,
  };

  void _received(Map<String, dynamic> data, (int, int) start, int bytes) {
    final key = _eventKey(data);
    if (key == null) return;
    _point('dart.receive', key.$1, key.$2, at: start, bytes: bytes);
    _span('dart.decode', key.$1, key.$2, start);
  }

  void _acknowledged(Map<String, dynamic> data) {
    final key = _eventKey(data);
    if (key == null) return;
    _point(
      'dart.ack',
      key.$1,
      key.$2,
      status:
          const ['rejected', 'dataset_rejected', 'error'].contains(data['type'])
          ? 1
          : 0,
      nativeApplyUs: (data['native_apply_us'] ?? data['apply_us']) as int?,
    );
  }

  /// Chrome Trace JSON plus raw QPC records for stage correlation.
  /// Live exports can be incomplete. Inspect metadata before using measurements.
  Map<String, Object?> toJson() {
    _captureNative();
    final records = [..._records, ..._nativeRecords]
      ..sort((a, b) => a.start.compareTo(b.start));
    final raw = records.map((record) => record.toJson()).toList();
    return {
      'schema': 1,
      'metadata': {
        'clock': 'Windows QueryPerformanceCounter',
        'origin_qpc': _clock.origin,
        'frequency': _clock.frequency,
        'cross_thread_order_uncertainty_ticks': 1,
        'process_id': pid,
        'capacity_per_side': capacity,
        'dart_dropped': _dropped,
        'native_dropped': _nativeDropped,
        'native_read_failed': _nativeError,
        'finalized': _nativeAttached && _reader == null,
        'capture_complete':
            _nativeAttached &&
            _reader == null &&
            !_nativeError &&
            _dropped == 0 &&
            _nativeDropped == 0,
        'scope': 'Opt-in publication and host readiness; excludes OS input, layout, GPU presentation and VM boot. Native dispatch covers synchronous handling; deferred diagnostic replies occur later. Tracing adds overhead.',
      },
      'records': raw,
      'traceEvents': records.map((record) {
        final duration = record.end - record.start;
        return <String, Object?>{
          'name': record.name,
          'cat': 'gpuidart',
          'ph': duration == 0 ? 'i' : 'X',
          if (duration == 0) 's': 't',
          'ts': (record.start - _clock.origin) * (1000000 / _clock.frequency),
          if (duration != 0) 'dur': duration * (1000000 / _clock.frequency),
          'pid': pid,
          'tid': record.thread,
          'args': {
            'operation': record.operation,
            'request': record.request,
            if (record.bytes != null) 'bytes': record.bytes,
            if (record.status != null) 'status': record.status,
            if (record.nativeApplyUs != null)
              'native_apply_us': record.nativeApplyUs,
          },
        };
      }).toList(),
      'displayTimeUnit': 'ms',
    };
  }

  Future<void> writeTo(String path) =>
      File(path).writeAsString(jsonEncode(toJson()));
}

final class _TraceRecord {
  const _TraceRecord(
    this.name,
    this.operation,
    this.request,
    this.start,
    this.end,
    this.thread, {
    this.bytes,
    this.status,
    this.nativeApplyUs,
  });
  final String name, operation;
  final int request, start, end, thread;
  final int? bytes, status, nativeApplyUs;

  factory _TraceRecord.fromNative(Object? value) {
    if (value is! Map<String, dynamic> ||
        !const [
          'native.parse',
          'native.enqueue_attempt',
          'native.submit_return',
          'native.dequeue',
          'native.dispatch',
          'native.emit',
          'native.run',
          'native.window_opened',
          'native.close',
        ].contains(value['name']) ||
        !const [
          'snapshot',
          'dataset',
          'diagnostic',
          'initial',
          'close',
          'failure',
        ].contains(value['operation'])) {
      throw const FormatException('Invalid native trace record');
    }
    for (final field in ['request', 'start', 'end', 'thread']) {
      if (value[field] is! int || (value[field] as int) < 0) {
        throw FormatException('Invalid native trace $field');
      }
    }
    if ((value['end'] as int) < (value['start'] as int) ||
        (value['bytes'] != null &&
            (value['bytes'] is! int || (value['bytes'] as int) < 0)) ||
        (value['status'] != null && value['status'] is! int)) {
      throw const FormatException('Invalid native trace duration or counters');
    }
    return _TraceRecord(
      value['name'] as String,
      value['operation'] as String,
      value['request'] as int,
      value['start'] as int,
      value['end'] as int,
      value['thread'] as int,
      bytes: value['bytes'] as int?,
      status: value['status'] as int?,
    );
  }

  Map<String, Object> toJson() => {
    'name': name,
    'operation': operation,
    'request': request,
    'start': start,
    'end': end,
    'thread': thread,
    'bytes': ?bytes,
    'status': ?status,
    'native_apply_us': ?nativeApplyUs,
  };
}

final class _TraceClock implements Finalizable {
  _TraceClock() {
    _finalizer.attach(this, _scratch.cast());
    if (_frequency(_scratch) == 0 || _scratch.value <= 0) {
      throw StateError('Windows QPC frequency is unavailable');
    }
    frequency = _scratch.value;
    origin = now().$1;
  }
  static final _library = DynamicLibrary.open('kernel32.dll');
  static final _counter = _library
      .lookupFunction<
        Int32 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('QueryPerformanceCounter');
  static final _frequency = _library
      .lookupFunction<
        Int32 Function(Pointer<Int64>),
        int Function(Pointer<Int64>)
      >('QueryPerformanceFrequency');
  static final _thread = _library
      .lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  final _scratch = calloc<Int64>();
  late final int frequency, origin;
  (int, int) now() {
    if (_counter(_scratch) == 0) throw StateError('Windows QPC is unavailable');
    return (_scratch.value, _thread());
  }
}

final class _NativeTraceBindings {
  _NativeTraceBindings(DynamicLibrary library) {
    try {
      final version = library.lookupFunction<Uint32 Function(), int Function()>(
        'gd_trace_version',
      );
      if (version() != 1) throw StateError('Unsupported native trace version');
      enable = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Size),
            int Function(Pointer<Void>, int)
          >('gd_trace_enable');
      read = library
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
            Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
          >('gd_trace_read');
    } on ArgumentError {
      throw StateError(
        'Native library does not support tracing; rebuild the DLL',
      );
    }
  }
  late final int Function(Pointer<Void>, int) enable;
  late final Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>) read;

  Map<String, dynamic> snapshot(_Bindings bindings, Pointer<Void> host) {
    final length = calloc<Size>();
    Pointer<Uint8> bytes = nullptr;
    try {
      bytes = read(host, length);
      if (bytes == nullptr ||
          length.value == 0 ||
          length.value > 16 * 1024 * 1024) {
        throw const FormatException('Invalid native trace buffer');
      }
      final value = jsonDecode(utf8.decode(bytes.asTypedList(length.value)));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid native trace JSON');
      }
      return value;
    } finally {
      if (bytes != nullptr) bindings.freeEvent(bytes, length.value);
      calloc.free(length);
    }
  }
}
