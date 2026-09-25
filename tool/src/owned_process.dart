import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:gpuidart/src/platform.dart';

/// A Unix session or Windows process tree created and owned by this tool.
class OwnedProcess {
  OwnedProcess._(this.process);
  final Process process;
  Future<void>? _stopping;

  static Future<OwnedProcess> start(
    String executable,
    List<String> arguments, {
    String? launcherPath,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async => OwnedProcess._(
    await Process.start(
      Platform.isWindows ? executable : launcherPath ?? resolveLauncher(),
      Platform.isWindows ? arguments : ['--session', executable, ...arguments],
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
    ),
  );

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    if (Platform.isWindows) {
      await Process.run('taskkill.exe', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      // Only this class's setsid launcher creates processes accepted here.
      // The group remains owned even if its Dart parent exited first.
      final kill = DynamicLibrary.process()
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'kill',
          );
      kill(-process.pid, ProcessSignal.sigterm.signalNumber);
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (kill(-process.pid, 0) == 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (kill(-process.pid, 0) == 0) {
        kill(-process.pid, ProcessSignal.sigkill.signalNumber);
      }
      // Covers a launch that failed before setsid could establish the group.
      process.kill(ProcessSignal.sigkill);
      // A stop may race setsid. Sweep the owned group after the parent exits.
      await process.exitCode.timeout(const Duration(seconds: 10));
      kill(-process.pid, ProcessSignal.sigkill.signalNumber);
    }
    await process.exitCode.timeout(const Duration(seconds: 10));
  }
}
