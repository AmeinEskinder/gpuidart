part of 'host.dart';

/// Dart owns child status because its macOS VM waits for any child process.
final class _Companion {
  _Companion(this.process, _Bindings bindings, Pointer<Void> host) {
    final notify = bindings.library.lookupFunction<_HostNative, _HostDart>(
      'gd_companion_exited',
    );
    exited = process.exitCode.then((status) {
      notify(host);
      _deadline?.cancel();
      return status;
    });
    unawaited(process.stdout.drain<void>());
    process.stderr.listen(stderr.add);
  }
  final Process process;
  late final Future<int> exited;
  Timer? _deadline;

  static Future<_Companion?> start(
    _Bindings bindings,
    String libraryPath,
    Pointer<Void> host,
  ) async {
    if (!Platform.isMacOS &&
        !(Platform.isLinux &&
            Platform.environment['GPUIDART_COMPANION'] == '1')) {
      return null;
    }
    final version = bindings.library
        .lookupFunction<Uint32 Function(), int Function()>(
          'gd_companion_version',
        )();
    // Explicit capability for the headless fault peer; it never opens AppKit.
    if (version == 0) return null;
    if (version != 2) {
      throw StateError(
        'Incompatible GPUI companion extension; rebuild the SDK and launcher',
      );
    }
    final launcher = resolveLauncher(libraryPath: libraryPath);
    final prepare = bindings.library
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>),
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Size>)
        >('gd_companion_prepare');
    final length = calloc<Size>();
    Pointer<Uint8> bytes = nullptr;
    late String socket;
    try {
      bytes = prepare(host, length);
      if (bytes == nullptr || length.value == 0 || length.value > 1024) {
        throw StateError('Could not prepare companion socket');
      }
      socket = utf8.decode(bytes.asTypedList(length.value));
    } finally {
      if (bytes != nullptr) bindings.freeEvent(bytes, length.value);
      calloc.free(length);
    }
    final process = await Process.start(launcher, [
      '--ui-host',
      libraryPath,
      socket,
    ]);
    return _Companion(process, bindings, host);
  }

  void armDeadline() {
    _deadline ??= Timer(
      const Duration(seconds: 4),
      () => process.kill(ProcessSignal.sigkill),
    );
  }

  Future<int> finish() async {
    armDeadline();
    try {
      return await exited;
    } finally {
      _deadline?.cancel();
    }
  }

  Future<void> abortStartup() async {
    process.kill(ProcessSignal.sigkill);
    await exited;
  }
}
