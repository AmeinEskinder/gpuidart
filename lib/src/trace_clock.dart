import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// System-wide clocks shared with native/src/clock.rs. These are never wall time.
abstract class TraceClock {
  TraceClock._();
  factory TraceClock() => switch (Platform.operatingSystem) {
    'windows' => _WindowsClock(),
    'linux' => _LinuxClock(),
    'macos' => _MacClock(),
    _ => throw UnsupportedError(
      'No GPUI trace clock for ${Platform.operatingSystem}',
    ),
  };
  late final int frequency, origin;
  String get name;
  String get epoch;
  String get suspendBehavior;
  int? get resolutionTicks => null;
  (int, int) now();
}

final class _WindowsClock extends TraceClock implements Finalizable {
  _WindowsClock() : super._() {
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
  @override
  String get name => 'Windows QueryPerformanceCounter';
  @override
  String get epoch => 'System QPC epoch; capture origin stored separately';
  @override
  String get suspendBehavior => 'Includes sleep and hibernation';
  @override
  (int, int) now() {
    if (_counter(_scratch) == 0) throw StateError('Windows QPC is unavailable');
    return (_scratch.value, _thread());
  }
}

final class _Timespec extends Struct {
  @Int64()
  external int seconds;
  @Int64()
  external int nanoseconds;
}

final class _LinuxClock extends TraceClock implements Finalizable {
  _LinuxClock() : super._() {
    _finalizer.attach(this, _scratch.cast());
    if (_resolution(1, _scratch) != 0) {
      throw StateError('CLOCK_MONOTONIC resolution is unavailable');
    }
    _resolutionTicks = _value;
    frequency = 1000000000;
    origin = now().$1;
  }
  static final _library = DynamicLibrary.open('libc.so.6');
  static final _counter = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)
      >('clock_gettime');
  static final _resolution = _library
      .lookupFunction<
        Int32 Function(Int32, Pointer<_Timespec>),
        int Function(int, Pointer<_Timespec>)
      >('clock_getres');
  static final _thread = _library
      .lookupFunction<Int32 Function(), int Function()>('gettid');
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  final _scratch = calloc<_Timespec>();
  late final int _resolutionTicks;
  int get _value =>
      _scratch.ref.seconds * 1000000000 + _scratch.ref.nanoseconds;
  @override
  String get name => 'Linux CLOCK_MONOTONIC';
  @override
  String get epoch => 'System boot, excluding suspended time';
  @override
  String get suspendBehavior =>
      'Excludes system suspend; frequency may be adjusted by the OS';
  @override
  int get resolutionTicks => _resolutionTicks;
  @override
  (int, int) now() {
    if (_counter(1, _scratch) != 0) {
      throw StateError('CLOCK_MONOTONIC is unavailable');
    }
    return (_value, _thread());
  }
}

final class _Timebase extends Struct {
  @Uint32()
  external int numerator;
  @Uint32()
  external int denominator;
}

final class _MacClock extends TraceClock implements Finalizable {
  _MacClock() : super._() {
    _finalizer.attach(this, _scratch.cast());
    final info = calloc<_Timebase>();
    try {
      final read = _library
          .lookupFunction<
            Int32 Function(Pointer<_Timebase>),
            int Function(Pointer<_Timebase>)
          >('mach_timebase_info');
      if (read(info) != 0 ||
          info.ref.numerator == 0 ||
          info.ref.denominator == 0 ||
          (1000000000 * info.ref.denominator) % info.ref.numerator != 0) {
        throw UnsupportedError('Unsupported Mach trace clock timebase');
      }
      frequency = 1000000000 * info.ref.denominator ~/ info.ref.numerator;
    } finally {
      calloc.free(info);
    }
    origin = now().$1;
  }
  static final _library = DynamicLibrary.open('/usr/lib/libSystem.B.dylib');
  static final _counter = _library
      .lookupFunction<Uint64 Function(), int Function()>('mach_absolute_time');
  static final _thread = _library
      .lookupFunction<
        Int32 Function(UintPtr, Pointer<Uint64>),
        int Function(int, Pointer<Uint64>)
      >('pthread_threadid_np');
  static final _finalizer = NativeFinalizer(calloc.nativeFree);
  final _scratch = calloc<Uint64>();
  @override
  String get name => 'macOS mach_absolute_time';
  @override
  String get epoch =>
      'System absolute uptime clock; capture origin stored separately';
  @override
  String get suspendBehavior =>
      'Excludes system sleep, per the Mach clock contract';
  @override
  (int, int) now() {
    final ticks = _counter();
    if (_thread(0, _scratch) != 0) {
      throw StateError('Native thread ID is unavailable');
    }
    return (ticks, _scratch.value);
  }
}
