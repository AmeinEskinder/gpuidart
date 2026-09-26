import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gpuidart/src/platform.dart';
import 'package:gpuidart/src/trace_clock.dart';

import '../src/commands.dart';
import '../src/owned_process.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 || args.length > 4) {
    throw ArgumentError(
      'Usage: run_baselines.dart NEW_OUTPUT_DIRECTORY NATIVE_DIRECTORY [REPETITIONS=3] [full|smoke]',
    );
  }
  final output = Directory(args[0]).absolute;
  if (output.existsSync()) {
    throw StateError('Refusing to overwrite baseline evidence');
  }
  output.createSync(recursive: true);
  final native = Directory(args[1]).absolute;
  final repetitions = args.length > 2 ? int.parse(args[2]) : 3;
  final smoke = args.length > 3 && args[3] == 'smoke';
  if (repetitions < 1 || repetitions > 20) {
    throw ArgumentError('Repetitions must be 1..20');
  }
  if (args.length > 3 && !['full', 'smoke'].contains(args[3])) {
    throw ArgumentError('Expected full or smoke');
  }
  final library = File('${native.path}/${nativeLibraryName('gpuidart')}');
  final suffix = Platform.isWindows ? '.exe' : '';
  final launcher = File('${native.path}/gpuidart-launcher$suffix');
  final executable = '${output.path}/capture$suffix';
  final metadata = <String, Object?>{
    'source': await command('git', ['rev-parse', 'HEAD']),
    'working_tree': await command('git', ['status', '--porcelain']),
    'os': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'rust': await command('rustc', ['--version']),
    'native_path': library.path,
    'native_sha256': await sha256
        .bind(library.openRead())
        .first
        .then((v) => '$v'),
    if (!Platform.isWindows)
      'launcher_sha256': await sha256
          .bind(launcher.openRead())
          .first
          .then((v) => '$v'),
    'repetitions': repetitions,
    'smoke': smoke,
    'scope': 'Sequential rotated fresh processes on one machine; release status depends on supplied native artifact. JIT includes dart run startup. Trace and plain runs are separate. No cross-platform hardware normalization or presentation claims.',
  };
  await command(Platform.resolvedExecutable, [
    'compile',
    'exe',
    '--define=gpuidart.packaged=true',
    'tool/performance/capture_baseline.dart',
    '-o',
    executable,
  ]);
  metadata['aot_sha256'] =
      '${await sha256.bind(File(executable).openRead()).first}';
  await File('${output.path}/metadata.json')
      .writeAsString(jsonEncode(metadata));
  final cases =
      <
        ({
          String mode,
          String control,
          int rows,
          String tracing,
          bool companion,
        })
      >[
        for (final mode in smoke ? ['aot'] : ['jit', 'aot'])
          for (final rows in smoke ? [0, 100000] : [0, 1000, 10000, 100000])
            for (final control
                in smoke ? ['host'] : ['data-only', 'library-only', 'host'])
              (
                mode: mode,
                control: control,
                rows: rows,
                tracing: 'trace',
                companion: Platform.isMacOS,
              ),
        if (!smoke) ...[
          for (final rows in [0, 100000])
            (
              mode: 'aot',
              control: 'host',
              rows: rows,
              tracing: 'plain',
              companion: Platform.isMacOS,
            ),
          if (Platform.isLinux)
            for (final rows in [0, 1000, 10000, 100000])
              (
                mode: 'aot',
                control: 'host',
                rows: rows,
                tracing: 'trace',
                companion: true,
              ),
        ],
      ];
  final clock = TraceClock();
  final results = <Map<String, Object?>>[];
  var failures = 0;
  for (var repetition = 0; repetition < repetitions; repetition++) {
    final rotated = [
      ...cases.skip(repetition % cases.length),
      ...cases.take(repetition % cases.length),
    ];
    for (final fixture in repetition.isEven ? rotated : rotated.reversed) {
      final name =
          '${fixture.mode}-${fixture.control}-${fixture.rows}-${fixture.tracing}-${fixture.companion ? 'companion' : 'direct'}-${repetition + 1}';
      final record = <String, Object?>{'name': name, 'passed': false};
      final reportPath = '${output.path}/$name.application.json';
      OwnedProcess? process;
      Future<String>? out, err;
      try {
        final start = clock.now().$1;
        record['driver_launch_ticks'] = start;
        process = await OwnedProcess.start(
          fixture.mode == 'aot' ? executable : Platform.resolvedExecutable,
          [
            if (fixture.mode == 'jit') ...[
              'run',
              'tool/performance/capture_baseline.dart',
            ],
            reportPath,
            '${fixture.rows}',
            fixture.control,
            fixture.tracing,
          ],
          launcherPath: launcher.path,
          environment: {
            'GPUIDART_LIBRARY': library.path,
            'GPUIDART_LAUNCHER': launcher.path,
            'GPUIDART_COMPANION': fixture.companion ? '1' : '0',
          },
        );
        out = process.process.stdout.transform(utf8.decoder).join();
        err = process.process.stderr.transform(utf8.decoder).join();
        final status = await process.process.exitCode.timeout(
          const Duration(seconds: 60),
        );
        record['exit_code'] = status;
        final app = jsonDecode(
          await File(reportPath).readAsString(),
        ) as Map<String, dynamic>;
        if (app['clock'] != clock.name || app['frequency'] != clock.frequency) {
          throw StateError('Driver/application clocks differ');
        }
        record['from_driver_launch_us'] = {
          for (final entry in (app['stages'] as Map).entries)
            entry.key:
                ((entry.value as int) - start) * 1000000 / clock.frequency,
        };
        if (app['trace'] case final Map trace) {
          final paint = (trace['records'] as List)
              .cast<Map>()
              .where((r) => r['name'] == 'native.first_content_paint')
              .toList();
          if (paint.length != 1) {
            throw StateError('Expected one first content-paint marker');
          }
          record['first_content_paint_from_launch_us'] =
              ((paint.single['start'] as int) - start) *
              1000000 /
              clock.frequency;
        }
        if (status != 0 || app['passed'] != true) {
          throw StateError('Application baseline failed');
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
  if (failures != 0) exitCode = 1;
}
