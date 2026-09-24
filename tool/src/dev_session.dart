import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

class DevSession {
  DevSession._(this.process, this.service, this.isolateId, this.directory);
  final Process process;
  final VmService service;
  final String isolateId;
  final Directory directory;

  static Future<DevSession> start({String entry = 'example/main.dart'}) async {
    final directory = await Directory.systemTemp.createTemp('gpuidart-vm-');
    final serviceInfo = File.fromUri(directory.uri.resolve('service.json'));
    final process = await Process.start(Platform.resolvedExecutable, [
      '--enable-vm-service=0',
      '--write-service-info=${serviceInfo.path}',
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      entry,
    ]);
    process.stdout.listen(stdout.add);
    process.stderr.listen(stderr.add);
    VmService? service;
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!serviceInfo.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('VM service did not start');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      final info =
          jsonDecode(await serviceInfo.readAsString()) as Map<String, dynamic>;
      final uri = Uri.parse(info['uri'] as String);
      service = await vmServiceConnectUri(
        uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
      );
      while (DateTime.now().isBefore(deadline)) {
        final vm = await service.getVM();
        for (final ref in vm.isolates ?? <IsolateRef>[]) {
          final isolate = await service.getIsolate(ref.id!);
          if (isolate.extensionRPCs?.contains('ext.gpuidart.reassemble') ??
              false) {
            return DevSession._(process, service, ref.id!, directory);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      throw StateError(
        'GPUI application did not register its reload extension',
      );
    } catch (_) {
      process.kill();
      await process.exitCode;
      await service?.dispose();
      await removeSessionDirectory(directory);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> call(String method) async =>
      (await service.callServiceExtension(
        'ext.gpuidart.$method',
        isolateId: isolateId,
      )).json!;

  Future<Map<String, dynamic>> reload() async {
    final report = await service.reloadSources(isolateId);
    if (report.success != true) {
      throw StateError('Dart rejected reload: ${report.json}');
    }
    return call('reassemble');
  }

  Future<void> close() async {
    try {
      await call('close');
      await process.exitCode.timeout(const Duration(seconds: 10));
    } finally {
      process.kill();
      await service.dispose();
      await removeSessionDirectory(directory);
    }
  }
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
