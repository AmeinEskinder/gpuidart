import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gpuidart/src/platform.dart';

import '../src/commands.dart';
import '../src/owned_process.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: run_snapshot_gate.dart NEW_OUTPUT_DIRECTORY NATIVE_DIRECTORY',
    );
  }
  final output = Directory(args[0]).absolute;
  if (output.existsSync()) throw StateError('Retain previous gate series');
  output.createSync(recursive: true);
  final native = Directory(args[1]).absolute.path;
  final library = '$native/${nativeLibraryName('gpuidart')}';
  final launcher =
      '$native/gpuidart-launcher${Platform.isWindows ? '.exe' : ''}';
  final executable = '${output.path}/gate${Platform.isWindows ? '.exe' : ''}';
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    'tool/performance/capture_snapshot_gate.dart',
    '-o',
    executable,
  ]);
  await File('${output.path}/metadata.json').writeAsString(
    jsonEncode({
      'source': await command('git', ['rev-parse', 'HEAD']),
      'working_tree': await command('git', ['status', '--porcelain']),
      'native_sha256': '${await sha256.bind(File(library).openRead()).first}',
      'aot_sha256': '${await sha256.bind(File(executable).openRead()).first}',
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'scope': 'Synthetic snapshot-heavy gate; three repetitions, rotated sizes and mode order. Uses supplied native artifact, whose compilation flags must be recorded separately.',
    }),
  );
  final results = <Object?>[];
  var failures = 0;
  for (var repetition = 0; repetition < 3; repetition++) {
    final sizes = [128, 512, 2048];
    final order = [...sizes.skip(repetition), ...sizes.take(repetition)];
    for (final fields in order) {
      for (final mode in repetition.isEven ? ['jit', 'aot'] : ['aot', 'jit']) {
        final name = '$mode-$fields-${repetition + 1}';
        final record = <String, Object?>{'name': name, 'passed': false};
        OwnedProcess? process;
        Future<String>? out, err;
        try {
          process = await OwnedProcess.start(
            mode == 'aot' ? executable : Platform.resolvedExecutable,
            [
              if (mode == 'jit') ...[
                'run',
                'tool/performance/capture_snapshot_gate.dart',
              ],
              '${output.path}/$name',
              '$fields',
            ],
            launcherPath: launcher,
            environment: {
              'GPUIDART_LIBRARY': library,
              'GPUIDART_LAUNCHER': launcher,
            },
          );
          out = process.process.stdout.transform(utf8.decoder).join();
          err = process.process.stderr.transform(utf8.decoder).join();
          final status = await process.process.exitCode.timeout(
            const Duration(seconds: 90),
          );
          record['exit_code'] = status;
          final report = jsonDecode(
            await File('${output.path}/$name/report.json').readAsString(),
          ) as Map;
          if (status != 0 || report['passed'] != true) {
            throw StateError('Gate fixture failed');
          }
          record['passed'] = true;
        } catch (error, stack) {
          record['error'] = '$error';
          record['stack'] = '$stack';
          failures++;
        } finally {
          await process?.stop();
          await File('${output.path}/$name.stdout.log')
              .writeAsString(await out ?? '');
          await File('${output.path}/$name.stderr.log')
              .writeAsString(await err ?? '');
          results.add(record);
          await File('${output.path}/summary.json').writeAsString(
            jsonEncode({
              'passed': failures == 0,
              'failures': failures,
              'runs': results,
            }),
          );
          stdout.writeln('$name: passed=${record['passed']}');
        }
      }
    }
  }
  if (failures != 0) exitCode = 1;
}
