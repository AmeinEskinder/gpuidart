import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/src/platform.dart';
import 'package:gpuidart/src/trace_clock.dart';

import 'src/commands.dart';
import 'src/owned_process.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: run_host_baselines.dart OUTPUT_DIRECTORY');
  }
  final output = Directory(args.single).absolute..createSync(recursive: true);
  final executable = '${output.path}/baseline';
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    'tool/capture_host_baseline.dart',
    '-o',
    executable,
  ]);
  final library = File('target/release/${nativeLibraryName('gpuidart')}')
      .absolute
      .path;
  final launcher = File('target/release/gpuidart-launcher').absolute.path;
  final clock = TraceClock();
  final results = <Map<String, dynamic>>[];
  for (var repetition = 0; repetition < 3; repetition++) {
    for (final mode in repetition.isEven ? ['jit', 'aot'] : ['aot', 'jit']) {
      final start = clock.now().$1;
      final process = await OwnedProcess.start(
        mode == 'aot' ? executable : Platform.resolvedExecutable,
        mode == 'aot' ? [] : ['run', 'tool/capture_host_baseline.dart'],
        launcherPath: launcher,
        environment: {
          'GPUIDART_LIBRARY': library,
          'GPUIDART_LAUNCHER': launcher,
        },
      );
      final stdoutText = process.process.stdout.transform(utf8.decoder).join();
      final stderrText = process.process.stderr.transform(utf8.decoder).join();
      final record = <String, dynamic>{
        'mode': mode,
        'repetition': repetition + 1,
        'driver_launch_ticks': start,
        'passed': false,
      };
      try {
        final status = await process.process.exitCode.timeout(
          const Duration(seconds: 45),
        );
        record['exit_code'] = status;
        record['stderr'] = await stderrText;
        record['stdout'] = await stdoutText;
        if (status != 0) throw StateError('Baseline exited with $status');
        final app = jsonDecode(
          record.remove('stdout') as String,
        ) as Map<String, dynamic>;
        record['application'] = app;
        if (app['passed'] != true ||
            app['frequency'] != clock.frequency ||
            app['clock'] != clock.name) {
          throw StateError('Invalid baseline or clock mismatch');
        }
        record['from_driver_launch_us'] = {
          for (final stage in (app['stages'] as Map<String, dynamic>).entries)
            stage.key:
                ((stage.value as int) - start) * 1000000 / clock.frequency,
        };
        record['passed'] = true;
      } catch (error) {
        record['error'] = '$error';
        rethrow;
      } finally {
        await process.stop();
        results.add(record);
        await File('${output.path}/$mode-${repetition + 1}.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(record)}\n',
        );
      }
    }
  }
  await File('${output.path}/summary.json').writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({
      'source': await command('git', ['rev-parse', 'HEAD']),
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'runs': results.map((r) => {'mode': r['mode'], 'repetition': r['repetition'], 'passed': r['passed'], 'from_driver_launch_us': r['from_driver_launch_us']}).toList(),
      'scope': 'Three instrumented repetitions per mode on one runner. Shared OS-clock stage boundaries. No input-to-present or cross-platform hardware-normalized comparison.',
    })}\n',
  );
}
