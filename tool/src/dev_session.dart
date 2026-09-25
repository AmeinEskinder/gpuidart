import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'owned_process.dart';

class DevSession {
  DevSession._(this._owned, this.service, this.isolateId, this.directory) {
    unawaited(process.exitCode.then((_) => _exited = true));
  }
  final OwnedProcess _owned;
  Process get process => _owned.process;
  final VmService service;
  final String isolateId;
  final Directory directory;
  bool _exited = false;
  Future<void>? _closing;

  static Future<DevSession> start({
    String entry = 'example/main.dart',
    List<String> arguments = const [],
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    final directory = await Directory.systemTemp.createTemp('gpuidart-vm-');
    final serviceInfo = File.fromUri(directory.uri.resolve('service.json'));
    late final OwnedProcess owned;
    try {
      owned = await OwnedProcess.start(Platform.resolvedExecutable, [
        '--enable-vm-service=0',
        '--write-service-info=${serviceInfo.path}',
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        entry,
        ...arguments,
      ]);
    } catch (_) {
      await removeSessionDirectory(directory);
      rethrow;
    }
    final process = owned.process;
    process.stdout.listen(stdout.add);
    process.stderr.listen(stderr.add);
    int? exitStatus;
    unawaited(
      process.exitCode.then((value) {
        exitStatus = value;
      }),
    );
    VmService? service;
    try {
      final deadline = DateTime.now().add(startupTimeout);
      Duration remaining() => deadline.difference(DateTime.now());
      final uri = await waitForVmServiceUri(
        serviceInfo,
        deadline: deadline,
        exitCode: process.exitCode,
      );
      service = await vmServiceConnectUri(
        uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
      ).timeout(remaining());
      while (DateTime.now().isBefore(deadline)) {
        if (exitStatus != null) {
          throw StateError(
            'Application exited with code $exitStatus before registering reload',
          );
        }
        final vm = await service.getVM().timeout(remaining());
        for (final ref in vm.isolates ?? <IsolateRef>[]) {
          // This isolate blocks in FFI for the lifetime of the native window.
          if (ref.name == 'gpui-native-loop') continue;
          final isolate = await service
              .getIsolate(ref.id!)
              .timeout(remaining());
          if (isolate.extensionRPCs?.contains('ext.gpuidart.reassemble') ??
              false) {
            return DevSession._(owned, service, ref.id!, directory);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError(
        'GPUI application did not register its reload extension',
      );
    } catch (error) {
      final startupExitStatus = exitStatus;
      await owned.stop();
      await service?.dispose();
      await removeSessionDirectory(directory);
      if (error is TimeoutException) {
        throw StateError(
          'Application startup timed out after ${startupTimeout.inSeconds}s: $entry. '
          'Call registerGpuiReload(host) after opening the host.',
        );
      }
      if (startupExitStatus != null) {
        throw StateError(
          'Application startup failed with exit code $startupExitStatus: $entry. $error',
        );
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> call(String method) async =>
      (await service
              .callServiceExtension(
                'ext.gpuidart.$method',
                isolateId: isolateId,
              )
              .timeout(const Duration(seconds: 10)))
          .json!;

  Future<Map<String, dynamic>> reload() async {
    final report = await service
        .reloadSources(isolateId)
        .timeout(const Duration(seconds: 10));
    if (report.success != true) {
      throw StateError('Dart rejected reload: ${report.json}');
    }
    return call('reassemble');
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      if (!_exited) {
        try {
          await call('close');
        } catch (_) {
          // The service can disconnect while the window is closing.
        }
        await process.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () async {
            await _owned.stop();
            return process.exitCode;
          },
        );
      }
    } finally {
      // A normally exited Dart process may still have native descendants.
      if (!Platform.isWindows) await _owned.stop();
      await service.dispose();
      await removeSessionDirectory(directory);
    }
  }
}

Future<Uri> waitForVmServiceUri(
  File serviceInfo, {
  required DateTime deadline,
  required Future<int> exitCode,
}) async {
  int? exitStatus;
  unawaited(exitCode.then((value) => exitStatus = value));
  while (DateTime.now().isBefore(deadline)) {
    if (exitStatus != null) {
      throw StateError(
        'Application exited with code $exitStatus before publishing its VM service URI',
      );
    }
    if (await serviceInfo.exists()) {
      try {
        if (jsonDecode(await serviceInfo.readAsString()) case {
          'uri': final String value,
        }) {
          final uri = Uri.tryParse(value);
          if (uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host.isNotEmpty) {
            return uri;
          }
        }
      } on FormatException {
        // The VM creates this file before its JSON write is complete.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'VM service did not publish a complete URI before the startup deadline',
  );
}

Future<void> removeSessionDirectory(Directory directory) async {
  final parent = Directory.systemTemp.absolute.path.toLowerCase();
  final path = directory.absolute.path.toLowerCase();
  if (!path.startsWith('$parent${Platform.pathSeparator}gpuidart-vm-') ||
      directory.parent.absolute.path.toLowerCase() != parent) {
    throw StateError('Unexpected VM session directory: ${directory.path}');
  }
  if (await directory.exists()) await directory.delete(recursive: true);
}
