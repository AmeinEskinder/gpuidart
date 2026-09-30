import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../native_probe/client.dart';
import '../src/commands.dart';
import '../src/toolchain.dart';

Future<void> main(List<String> args) async {
  final output = Directory(args.isEmpty ? 'build/platform-probe' : args.single)
      .absolute;
  output.createSync(recursive: true);
  final results = <Map<String, Object?>>[];
  Future<Map<String, Object?>> run(
    String name,
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 40),
    bool driveInput = false,
    bool companion = false,
  }) async {
    final watch = Stopwatch()..start();
    final stdoutFile = File('${output.path}/$name.stdout.log').openWrite();
    final stderrFile = File('${output.path}/$name.stderr.log').openWrite();
    var timedOut = false;
    int? status;
    Object? error;
    String? inputError;
    final events = <Map<String, dynamic>>[];
    Process? child;
    StreamSubscription<String>? outputEvents;
    StreamSubscription<List<int>>? errorEvents;
    Completer<int>? renderReady;
    Future<void>? driverDone;
    Future<void> stop(Process process) async {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    }

    try {
      final process = child = await startCommand(
        executable,
        arguments,
        environment: companion
            ? {'GPUIDART_PROBE_INPUT': '0', 'GPUIDART_PROBE_DISPATCH': '0'}
            : null,
      );
      final rendered = Completer<int>();
      renderReady = rendered;
      final outputDone = Completer<void>();
      outputEvents = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              stdoutFile.writeln(line);
              if (!line.startsWith('{')) return;
              try {
                if (jsonDecode(line) case final Map<String, dynamic> event) {
                  events.add(event);
                  if (driveInput &&
                      !rendered.isCompleted &&
                      event['stage'] == 'render' &&
                      event['pid'] == process.pid) {
                    rendered.complete(process.pid);
                  }
                }
              } on FormatException {
                // A dependency can also write plain text to stdout.
              }
            },
            onDone: () {
              if (driveInput && !rendered.isCompleted) {
                rendered.completeError(
                  StateError('Process exited before its first render'),
                );
              }
              if (!outputDone.isCompleted) outputDone.complete();
            },
            onError: (Object exception, StackTrace stack) {
              if (driveInput && !rendered.isCompleted) {
                rendered.completeError(exception, stack);
              }
              if (!outputDone.isCompleted) {
                outputDone.completeError(exception, stack);
              }
            },
            cancelOnError: true,
          );
      final driver = driverDone = driveInput
          ? rendered.future
                .then(injectInput)
                .then<void>(
                  (_) {},
                  onError: (Object error) {
                    inputError = error.toString();
                  },
                )
          : Future<void>.value();
      final errorDone = Completer<void>();
      errorEvents = process.stderr.listen(
        stderrFile.add,
        onDone: () {
          if (!errorDone.isCompleted) errorDone.complete();
        },
        onError: (Object exception, StackTrace stack) {
          if (!errorDone.isCompleted) {
            errorDone.completeError(exception, stack);
          }
        },
        cancelOnError: true,
      );
      final exit = process.exitCode.then<void>((code) => status = code);
      final completed = Future.wait<void>([
        exit,
        outputDone.future,
        errorDone.future,
        driver,
      ], eagerError: true).then<void>((_) {});
      await completed.timeout(
        timeout,
        onTimeout: () async {
          timedOut = true;
          await stop(process);
          status = await process.exitCode.timeout(const Duration(seconds: 5));
        },
      );
    } catch (exception) {
      error = exception.toString();
      if (child != null && status == null) {
        await stop(child);
        status = await child.exitCode.timeout(const Duration(seconds: 5));
      }
    } finally {
      Future<bool> settle(
        FutureOr<Object?> Function() operation,
        String stream, {
        Duration timeout = const Duration(seconds: 5),
      }) async {
        try {
          await Future<Object?>.sync(operation).timeout(timeout);
          return true;
        } catch (exception) {
          error ??= '$stream collection failed: $exception';
          return false;
        }
      }

      if (driveInput && renderReady != null && !renderReady.isCompleted) {
        renderReady.completeError(
          StateError('Probe stopped before its first render'),
        );
      }
      if (driverDone != null) {
        await settle(
          () => driverDone,
          'input driver',
          timeout: const Duration(seconds: 10),
        );
      }
      final outputStopped =
          outputEvents == null || await settle(outputEvents.cancel, 'stdout');
      final errorStopped =
          errorEvents == null || await settle(errorEvents.cancel, 'stderr');
      if (outputStopped) await settle(stdoutFile.close, 'stdout log');
      if (errorStopped) await settle(stderrFile.close, 'stderr log');
    }
    final rejectedThread =
        Platform.isMacOS &&
        status == 1 &&
        events.any(
          (event) =>
              event['stage'] == 'rejected_non_main_thread' &&
              event['main_thread'] == 0,
        );
    if (!rejectedThread &&
        (name.startsWith('rust-') ||
            name == 'dart-jit' ||
            name == 'dart-aot')) {
      final beforeQuit = events
          .where((event) => event['stage'] == 'before_quit')
          .firstOrNull;
      if (beforeQuit == null ||
          beforeQuit['detail']['resized_render'] != true) {
        error ??= 'No checkpoint proving resized rendering before quit';
      }
      if ((Platform.environment['GPUIDART_PROBE_INPUT'] == '1' ||
              Platform.environment['GPUIDART_PROBE_DISPATCH'] == '1') &&
          !companion &&
          (beforeQuit?['detail']['input_matches'] != true ||
              (beforeQuit?['detail']['clicks'] as int? ?? 0) < 1)) {
        error ??= 'Input and click checkpoint missing';
      }
      if (!Platform.isMacOS &&
          !events.any((event) => event['stage'] == 'run_return')) {
        error ??= 'Native loop did not report returning';
      }
    }
    final result = <String, Object?>{
      'name': name,
      'executable': executable,
      'arguments': arguments,
      'exit_code': status,
      'timeout': timedOut,
      'error': error,
      'elapsed_ms': watch.elapsedMilliseconds,
      'input_driver_error': inputError,
      'unsupported_non_main_thread': rejectedThread,
    };
    results.add(result);
    File('${output.path}/results.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'os': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'display': Platform.environment['DISPLAY'],
        'wayland_display': Platform.environment['WAYLAND_DISPLAY'],
        'results': results,
        'limits': 'Probe only. No IME, clean-machine or presentation claim.',
      }),
    );
    stdout.writeln(jsonEncode(result));
    return result;
  }

  await run('source', 'git', ['rev-parse', 'HEAD']);
  await run('rust', 'rustc', ['-vV']);
  if (Platform.isMacOS) {
    await run('hardware', 'system_profiler', [
      'SPHardwareDataType',
      'SPDisplaysDataType',
    ]);
    await run('os', 'sw_vers', []);
    await run('metal', await nativeProbe(), ['metal']);
  } else if (Platform.isLinux) {
    await run('os', 'uname', ['-a']);
    await run('vulkan', 'vulkaninfo', ['--summary']);
    await run('display', 'xrandr', ['--verbose']);
    await run('libc', 'ldd', ['--version']);
  }
  final suffix = Platform.isWindows ? '.exe' : '';
  final native = File('target/debug/gpuidart-platform-window$suffix')
      .absolute
      .path;
  final library = File(
    'target/debug/${Platform.isWindows
        ? 'gpuidart_platform_probe.dll'
        : Platform.isMacOS
        ? 'libgpuidart_platform_probe.dylib'
        : 'libgpuidart_platform_probe.so'}',
  ).absolute.path;
  final driveInput =
      Platform.isLinux && Platform.environment['GPUIDART_PROBE_INPUT'] == '1';
  final nativeMain = await run('rust-main', native, [], driveInput: driveInput);
  final nativeWorker = await run('rust-worker', native, [
    '--worker',
  ], driveInput: driveInput);
  final jit = await run('dart-jit', dartExecutable, [
    '--enable-vm-service=0',
    'tool/platform_probe/probe.dart',
    library,
  ], driveInput: driveInput);
  final aotPath = '${output.path}/probe$suffix';
  final compile = await run('aot-compile', dartExecutable, [
    'compile',
    'exe',
    'tool/platform_probe/probe.dart',
    '-o',
    aotPath,
  ], timeout: const Duration(minutes: 2));
  final aot = compile['exit_code'] == 0
      ? await run('dart-aot', aotPath, [library], driveInput: driveInput)
      : null;

  final companionJit = await run('companion-jit', dartExecutable, [
    'tool/platform_probe/companion.dart',
    native,
  ], companion: true);
  final companionAotPath = '${output.path}/companion$suffix';
  final companionCompile = await run('companion-compile', dartExecutable, [
    'compile',
    'exe',
    'tool/platform_probe/companion.dart',
    '-o',
    companionAotPath,
  ], timeout: const Duration(minutes: 2));
  final companionAot = companionCompile['exit_code'] == 0
      ? await run('companion-aot', companionAotPath, [native], companion: true)
      : null;
  final reload = await run(
    'companion-reload',
    dartExecutable,
    ['tool/platform_probe/reload.dart', native, '${output.path}/reload.json'],
    companion: true,
    timeout: const Duration(seconds: 45),
  );

  final ffiReload = !Platform.isMacOS
      ? await run(
          'ffi-reload',
          dartExecutable,
          [
            'tool/platform_probe/reload_ffi.dart',
            library,
            '${output.path}/reload-ffi.json',
          ],
          companion: true,
          timeout: const Duration(seconds: 45),
        )
      : null;

  bool successful(Map<String, Object?>? result) =>
      result?['exit_code'] == 0 &&
      result?['timeout'] == false &&
      result?['input_driver_error'] == null &&
      result?['error'] == null;
  // macOS worker rejection is an explicit negative capability check. Only the
  // companion candidate can satisfy its successful Dart launch/reload checks.
  final passed =
      [
        nativeMain,
        if (!Platform.isMacOS) nativeWorker,
        if (!Platform.isMacOS) jit,
        compile,
        if (!Platform.isMacOS) aot,
        companionJit,
        companionCompile,
        companionAot,
        reload,
        if (!Platform.isMacOS) ffiReload,
      ].every(successful) &&
      (!Platform.isMacOS ||
          [nativeWorker, jit, aot].every(
            (result) =>
                result?['unsupported_non_main_thread'] == true &&
                result?['timeout'] == false,
          ));
  stdout.writeln(
    'Applicable launch checks passed: $passed. See ${output.path}',
  );
  if (!passed) exitCode = 1;
}

Future<void> injectInput(int pid) async {
  Future<String> xdotool(List<String> arguments) async {
    final process = await startCommand('xdotool', arguments);
    final output = utf8.decodeStream(process.stdout);
    final errors = utf8.decodeStream(process.stderr);
    final status = await process.exitCode.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw TimeoutException('xdotool $arguments');
      },
    );
    final text = await output;
    final error = await errors;
    if (status != 0) throw StateError('xdotool exited $status: $error');
    return text.trim();
  }

  final window = (await xdotool([
    'search',
    '--sync',
    '--all',
    '--onlyvisible',
    '--pid',
    '$pid',
    '--name',
    '^GPUI-Dart platform probe\$',
  ])).split('\n').single;
  await xdotool([
    'windowactivate',
    '--sync',
    window,
    'mousemove',
    '--window',
    window,
    '80',
    '60',
    'click',
    '1',
    'type',
    '--clearmodifiers',
    '--delay',
    '30',
    'gpui-probe',
  ]);
  await xdotool(['mousemove', '--window', window, '80', '105', 'click', '1']);
}
