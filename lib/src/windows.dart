import 'dart:ffi';

/// Select DPI awareness before GPUI creates its first window. A packaged EXE
/// already has this setting in its manifest; Dart JIT needs the API call.
void configureWindowsDpi() {
  final user32 = DynamicLibrary.open('user32.dll');
  final current = user32
      .lookupFunction<IntPtr Function(IntPtr), int Function(int)>(
        'GetDpiAwarenessContextForProcess',
      );
  final equal = user32
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'AreDpiAwarenessContextsEqual',
      );
  if (equal(current(0), -4) != 0) return;
  final configure = user32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'SetProcessDpiAwarenessContext',
      );
  if (configure(-4) == 0 || equal(current(0), -4) == 0) {
    throw StateError(
      'GPUI requires PerMonitorV2 DPI awareness before any window is created. '
      'Check the executable manifest and earlier DPI configuration.',
    );
  }
}
