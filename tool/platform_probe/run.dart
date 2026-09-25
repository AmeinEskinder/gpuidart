import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }) async {
    final watch = Stopwatch()..start();
    final stdoutFile = File('${output.path}/$name.stdout.log').openWrite();
    final stderrFile = File('${output.path}/$name.stderr.log').openWrite();
    var timedOut = false;
    int? status;
    Object? error;
    try {
      final process = await Process.start(executable, arguments);
      final out = stdoutFile.addStream(process.stdout);
      final err = stderrFile.addStream(process.stderr);
      status = await process.exitCode.timeout(
        timeout,
        onTimeout: () async {
          timedOut = true;
          if (Platform.isWindows) {
            await Process.run('taskkill', [
              '/PID',
              '${process.pid}',
              '/T',
              '/F',
            ]);
          } else {
            process.kill(ProcessSignal.sigkill);
          }
          return await process.exitCode.timeout(const Duration(seconds: 5));
        },
      );
      await Future.wait([out, err]);
    } catch (exception) {
      error = exception.toString();
    } finally {
      await stdoutFile.close();
      await stderrFile.close();
    }
    final result = <String, Object?>{
      'name': name,
      'executable': executable,
      'arguments': arguments,
      'exit_code': status,
      'timeout': timedOut,
      'error': error,
      'elapsed_ms': watch.elapsedMilliseconds,
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
  final nativeMain = await run('rust-main', native, []);
  final nativeWorker = await run('rust-worker', native, ['--worker']);
  final jit = await run('dart-jit', Platform.resolvedExecutable, [
    '--enable-vm-service=0',
    'tool/platform_probe/probe.dart',
    library,
  ]);
  final aotPath = '${output.path}/probe$suffix';
  final compile = await run('aot-compile', Platform.resolvedExecutable, [
    'compile',
    'exe',
    'tool/platform_probe/probe.dart',
    '-o',
    aotPath,
  ], timeout: const Duration(minutes: 2));
  final aot = compile['exit_code'] == 0
      ? await run('dart-aot', aotPath, [library])
      : null;

  bool successful(Map<String, Object?>? result) =>
      result?['exit_code'] == 0 && result?['timeout'] == false;
  // macOS worker rejection is retained as an unsupported launcher result.
  // It is never counted as a successful window, callback or reload check.
  final passed = [
    nativeMain,
    nativeWorker,
    jit,
    compile,
    aot,
  ].every(successful);
  stdout.writeln('All launch strategies passed: $passed. See ${output.path}');
  if (!passed) exitCode = 1;
}
