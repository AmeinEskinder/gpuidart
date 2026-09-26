import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../src/commands.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: run_encoding.dart NEW_DIRECTORY');
  }
  final output = Directory(args[0]).absolute;
  if (output.existsSync()) throw StateError('Retain previous encoding series');
  output.createSync(recursive: true);
  final binary = '${output.path}/capture${Platform.isWindows ? '.exe' : ''}';
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    'tool/performance/capture_encoding.dart',
    '-o',
    binary,
  ]);
  final checks = await command(binary, ['--self-test']);
  await File('${output.path}/metadata.json').writeAsString(
    jsonEncode({
      'source': await command('git', ['rev-parse', 'HEAD']),
      'working_tree': await command('git', ['status', '--porcelain']),
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'aot_sha256': '${await sha256.bind(File(binary).openRead()).first}',
      'checks': checks,
    }),
  );
  final runs = <Object?>[];
  final hashes = <String, String>{};
  var failures = 0;
  const fixtures = ['cell', 'snapshot', 'initial', 'unicode'];
  for (var repetition = 0; repetition < 3; repetition++) {
    for (var index = 0; index < fixtures.length; index++) {
      final fixture = fixtures[(index + repetition) % fixtures.length];
      for (final encoder
          in (index + repetition).isEven
              ? ['legacy', 'fused']
              : ['fused', 'legacy']) {
        for (final mode
            in repetition.isEven ? ['jit', 'aot'] : ['aot', 'jit']) {
          final name = '$mode-$fixture-$encoder-${repetition + 1}';
          final record = <String, Object?>{
            'name': name,
            'mode': mode,
            'passed': false,
          };
          try {
            final result = await Process.run(
              mode == 'aot' ? binary : Platform.resolvedExecutable,
              [
                if (mode == 'jit') ...[
                  'run',
                  'tool/performance/capture_encoding.dart',
                ],
                '${output.path}/$name.json',
                encoder,
                fixture,
              ],
            ).timeout(const Duration(seconds: 90));
            await File('${output.path}/$name.stdout.log')
                .writeAsString('${result.stdout}');
            await File('${output.path}/$name.stderr.log')
                .writeAsString('${result.stderr}');
            record['exit_code'] = result.exitCode;
            if (result.exitCode != 0) {
              throw StateError('Encoder process failed');
            }
            final report = jsonDecode(
              await File('${output.path}/$name.json').readAsString(),
            ) as Map;
            final hash = report['sha256'] as String;
            if (hashes.putIfAbsent(fixture, () => hash) != hash) {
              throw StateError('Encoder output differs');
            }
            record['passed'] = report['passed'] == true;
          } catch (error, stack) {
            failures++;
            record['error'] = '$error';
            record['stack'] = '$stack';
          }
          runs.add(record);
          await File('${output.path}/summary.json').writeAsString(
            jsonEncode({
              'passed': failures == 0,
              'failures': failures,
              'runs': runs,
            }),
          );
          stdout.writeln('$name: passed=${record['passed']}');
        }
      }
    }
  }
  if (failures != 0) exitCode = 1;
}
