import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main() async {
  final fixture = await Directory('.cache').createTemp('watchlist-launcher-');
  final app = await File('example/watchlist/app.dart')
      .copy('${fixture.path}/app.dart');
  final entry = await File('example/watchlist/main.dart')
      .copy('${fixture.path}/main.dart');
  final process = await Process.start(Platform.resolvedExecutable, [
    'run',
    'tool/dev.dart',
    entry.absolute.path,
  ]);
  final serviceUri = Completer<Uri>();
  final watching = Completer<void>();
  final reloaded = Completer<void>();
  final errors = StringBuffer();
  final out = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdout.writeln('launcher: $line');
        const prefix = 'The Dart VM service is listening on ';
        if (line.startsWith(prefix) && !serviceUri.isCompleted) {
          serviceUri.complete(Uri.parse(line.substring(prefix.length)));
        }
        if (line.startsWith('Watching ') && !watching.isCompleted) {
          watching.complete();
        }
        if (line.startsWith('Reloaded:') && !reloaded.isCompleted) {
          reloaded.complete();
        }
      });
  final err = process.stderr.transform(utf8.decoder).listen(errors.write);
  VmService? service;
  try {
    final uri = await serviceUri.future.timeout(const Duration(seconds: 30));
    await watching.future.timeout(const Duration(seconds: 30));
    service = await vmServiceConnectUri(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString(),
    );
    final vm = await service.getVM();
    String? isolateId;
    for (final ref in vm.isolates ?? <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      if (isolate.extensionRPCs?.contains('ext.gpuidart.inspect') ?? false) {
        isolateId = ref.id;
        break;
      }
    }
    if (isolateId == null) {
      throw StateError('Launcher did not expose the application extensions');
    }
    final source = await app.readAsString();
    await app.writeAsString(
      source.replaceFirst("'Market watch'", "'Market watch from file watcher'"),
    );
    await reloaded.future.timeout(const Duration(seconds: 30));
    final state = (await service.callServiceExtension(
      'ext.gpuidart.inspect',
      isolateId: isolateId,
    )).json!;
    if (state['state']['labels']['title'] != 'Market watch from file watcher') {
      throw StateError('File watcher did not apply changed code');
    }
    final close = await Process.run('powershell.exe', [
      '-NoProfile',
      '-File',
      'tool/windows/watchlist_probe.ps1',
      '-AppProcessId',
      '${vm.pid!}',
      '-Step',
      'close',
    ]);
    if (close.exitCode != 0) {
      throw StateError('Window close failed: ${close.stderr}');
    }
    final status = await process.exitCode.timeout(const Duration(seconds: 15));
    if (status != 0) throw StateError('Launcher exited with $status: $errors');
    await Directory('reports/sdk').create(recursive: true);
    await File('reports/sdk/launcher.json').writeAsString(
      '${jsonEncode({'passed': true, 'custom_entry': entry.path, 'file_save_reloaded': true, 'window_close_stopped_launcher': true, 'close_method': 'WM_CLOSE to application HWND', 'exit_code': status})}\n',
    );
    stdout.writeln(
      'PASS: launcher watched a custom entry directory, reloaded saved code and exited after window close.',
    );
  } catch (error) {
    stderr.writeln('Launcher check failed: $error\n$errors');
    rethrow;
  } finally {
    process.kill();
    await process.exitCode;
    await service?.dispose();
    await out.cancel();
    await err.cancel();
  }
}
