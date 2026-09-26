import 'dart:convert';
import 'dart:io';

/// Linux-only external bus observer. Neither values nor names enter its report.
class CacheEvents {
  CacheEvents._(this.process, this.output, this.errors);
  final Process process;
  final File output;
  final Future<String> errors;
  Future<Map<String, dynamic>>? _ending;

  static Future<CacheEvents> start(int pid, String path) async {
    final output = File(path);
    if (output.existsSync()) throw StateError('Refusing to replace $path');
    final process = await Process.start('/usr/bin/python3', [
      'tool/accessibility/cache_events.py',
      '$pid',
      path,
    ]);
    final errors = process.stderr.transform(utf8.decoder).join();
    try {
      final ready = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 10));
      if (ready != 'ready') {
        throw StateError('Cache monitor did not initialize');
      }
      return CacheEvents._(process, output, errors);
    } catch (error) {
      process.kill();
      await process.exitCode;
      throw StateError('$error: ${await errors}');
    }
  }

  Future<Map<String, dynamic>> finish() => _ending ??= _finish();

  Future<Map<String, dynamic>> _finish() async {
    Object? stopError;
    try {
      process.stdin.writeln('stop');
      await process.stdin.close();
    } catch (error) {
      // A failed observer may already have exited; still reap it and read its report.
      stopError = error;
    }
    int status;
    try {
      status = await process.exitCode.timeout(const Duration(seconds: 10));
    } catch (_) {
      process.kill();
      await process.exitCode;
      rethrow;
    }
    final report =
        jsonDecode(await output.readAsString()) as Map<String, dynamic>;
    final stderr = await errors;
    if (stderr.isNotEmpty) report['client_stderr'] = stderr;
    if (stopError != null) report['stop_error'] = '$stopError';
    if (status != 0 || report['passed'] != true || stopError != null) {
      throw StateError('External cache signals failed: $report');
    }
    return report;
  }
}
