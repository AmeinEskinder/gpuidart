import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../src/commands.dart';
import '../src/owned_process.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    throw ArgumentError(
      'Usage: run_strategies.dart NEW_OUTPUT_DIRECTORY BINARY LAUNCHER REPETITIONS',
    );
  }
  final output = Directory(args[0]).absolute;
  if (output.existsSync()) throw StateError('Retain previous strategy series');
  output.createSync(recursive: true);
  final binary = File(args[1]).absolute.path;
  final launcher = File(args[2]).absolute.path;
  final repetitions = int.parse(args[3]);
  if (repetitions < 1) throw ArgumentError('Positive repetitions required');
  final executable =
      '${output.path}/capture${Platform.isWindows ? '.exe' : ''}';
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    'tool/performance/capture_strategy.dart',
    '-o',
    executable,
  ]);
  await File('${output.path}/metadata.json').writeAsString(
    jsonEncode({
      'source': await command('git', ['rev-parse', 'HEAD']),
      'working_tree': await command('git', ['status', '--porcelain']),
      'binary_sha256': '${await sha256.bind(File(binary).openRead()).first}',
      'launcher_sha256':
          '${await sha256.bind(File(launcher).openRead()).first}',
      'aot_sha256': '${await sha256.bind(File(executable).openRead()).first}',
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'repetitions': repetitions,
      'scope': 'Common experimental framed process transport and fixed layout; not shipping FFI. Rotated sizes/strategies and reversed JIT/AOT order. Native compilation flags recorded by caller. Failed runs retained.',
    }),
  );
  final results = <Object?>[];
  var failures = 0;
  const strategies = ['snapshot', 'subviews', 'patches'];
  const sizes = [128, 512, 2048];
  for (var repetition = 0; repetition < repetitions; repetition++) {
    for (var sizeIndex = 0; sizeIndex < sizes.length; sizeIndex++) {
      final fields = sizes[(sizeIndex + repetition) % sizes.length];
      for (var index = 0; index < strategies.length; index++) {
        final strategy =
            strategies[(index + repetition + sizeIndex) % strategies.length];
        for (final mode
            in repetition.isEven ? ['jit', 'aot'] : ['aot', 'jit']) {
          final name = '$mode-$fields-$strategy-${repetition + 1}';
          final record = <String, Object?>{'name': name, 'passed': false};
          OwnedProcess? process;
          Future<String>? out, err;
          try {
            process = await OwnedProcess.start(
              mode == 'aot' ? executable : Platform.resolvedExecutable,
              [
                if (mode == 'jit') ...[
                  'run',
                  'tool/performance/capture_strategy.dart',
                ],
                '${output.path}/$name',
                binary,
                launcher,
                strategy,
                '$fields',
              ],
              launcherPath: launcher,
            );
            out = process.process.stdout.transform(utf8.decoder).join();
            err = process.process.stderr.transform(utf8.decoder).join();
            final status = await process.process.exitCode.timeout(
              const Duration(seconds: 180),
            );
            record['exit_code'] = status;
            final report = jsonDecode(
              await File('${output.path}/$name/report.json').readAsString(),
            ) as Map;
            if (status != 0 || report['passed'] != true) {
              throw StateError('Strategy fixture failed');
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
  }
  if (failures != 0) exitCode = 1;
}
