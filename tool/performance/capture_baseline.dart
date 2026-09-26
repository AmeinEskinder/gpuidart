import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';
import 'package:gpuidart/src/trace_clock.dart';
import 'package:gpuidart/tracing.dart';

/// One fresh process per fixture. The driver timestamps immediately before spawn.
Future<void> main(List<String> args) async {
  final clockInit = Stopwatch()..start();
  final clock = TraceClock();
  final mainTick = clock.now().$1;
  clockInit.stop();
  if (args.length != 4) {
    throw ArgumentError(
      'Usage: capture_baseline.dart OUTPUT ROWS host|data-only|library-only trace|plain',
    );
  }
  final output = File(args[0]);
  final rows = int.parse(args[1]);
  final control = args[2];
  if (rows < 0 ||
      rows > 100000 ||
      !['host', 'data-only', 'library-only'].contains(control) ||
      !['trace', 'plain'].contains(args[3])) {
    throw ArgumentError('Invalid baseline fixture');
  }
  final stages = <String, int>{'dart_main_after_clock_init': mainTick};
  Map<String, Object> dartMemory() => {
    'pid': pid,
    'rss_bytes': ProcessInfo.currentRss,
    'peak_rss_bytes': ProcessInfo.maxRss,
    'source': 'Dart ProcessInfo; process RSS, not Dart heap size',
  };
  final memory = <String, Object?>{'at_main': dartMemory()};
  final report = <String, Object?>{
    'passed': false,
    'rows': rows,
    'control': control,
    'mode': const bool.fromEnvironment('gpuidart.packaged') ? 'aot' : 'jit',
    'clock': clock.name,
    'frequency': clock.frequency,
    'clock_init_us': clockInit.elapsedMicroseconds,
    'stages': stages,
    'memory': memory,
  };
  final trace = control == 'host' && args[3] == 'trace'
      ? GpuiTrace(capacity: 2048)
      : null;
  GpuiHost? host;
  try {
    final data = rows == 0
        ? null
        : TableDataset(
            'records',
            columns: ['ID', 'Value'],
            rows: List.generate(rows, (i) => ['$i', 'Row $i']),
          );
    stages['records_constructed'] = clock.now().$1;
    memory['after_records'] = dartMemory();
    if (control == 'library-only') {
      final beforeLoad = clock.now().$1;
      memory['library_loaded'] = readRuntimeInfo();
      stages['library_loaded'] = clock.now().$1;
      report['library_probe_start'] = beforeLoad;
    }
    if (control == 'host') {
      host = await GpuiHost.openView(
        () => UiColumn('root', [
          const UiText('title', 'Startup and retained-data fixture'),
          if (data != null) const UiTable('table', dataset: 'records'),
        ]),
        datasets: [?data],
        trace: trace,
        window: const GpuiWindowOptions(
          title: 'GPUI-Dart baseline',
          width: 960,
          height: 640,
        ),
      );
      stages['host_ready'] = clock.now().$1;
      final state = await host.diagnose('repaint', {'frames': 2});
      stages['verified_draw_ack'] = clock.now().$1;
      report['window'] = state['window'];
      report['native'] = state['native'];
      if (data != null) {
        final cell = await host.diagnose('cell', {
          'dataset': 'records',
          'row': rows - 1,
          'column': 1,
        });
        if (cell['value'] != 'Row ${rows - 1}') {
          throw StateError('Initial dataset mismatch');
        }
        if ((state['native'] as Map)['rows_constructed'] as int >= 1000) {
          throw StateError('Unexpected nonvirtualized construction');
        }
      }
    }
    Future<Map<String, Object?>> sample() async {
      if (control == 'data-only') return {'application': dartMemory()};
      final ui = host == null ? null : await host.diagnose('runtime');
      final app = readRuntimeInfo();
      return {
        'roles': {'application': app['pid'], 'ui': ?ui?['pid']},
        'by_pid': {'${ui?['pid']}': ?ui, '${app['pid']}': app},
        'application_process_info': dartMemory(),
      };
    }

    memory['after_ready'] = await sample();
    stages['idle_start'] = clock.now().$1;
    final settled = <Object?>[];
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      settled.add(await sample());
    }
    stages['idle_end'] = clock.now().$1;
    memory['settled_samples'] = settled;
    // Read after the idle interval to keep the authoritative dataset live in controls.
    report['retained_last_cell'] = data?.row(rows - 1)[1];
    if (host != null) {
      final roundTrips = <int>[];
      for (var i = 0; i < 20; i++) {
        final start = clock.now().$1;
        await host.diagnose('inspect');
        roundTrips.add(clock.now().$1 - start);
      }
      report['inspect_round_trip_ticks'] = roundTrips;
      report['metrics'] = host.metrics.read();
    }
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await host?.close();
    } catch (error) {
      report['shutdown_error'] = '$error';
      report['passed'] = false;
      exitCode = 1;
    }
    if (trace != null) {
      report['trace'] = trace.toJson();
      if (((report['trace'] as Map)['metadata'] as Map)['capture_complete'] !=
          true) {
        report['passed'] = false;
        report['trace_error'] = 'Capture incomplete';
        exitCode = 1;
      }
    }
    report['scope'] = 'Fresh process, instrumented startup and CPU content paint; no presentation measurement. Three settled samples, no forced GC. OS lifetime peaks are separate from observed samples. Data-only control never loads the native library. Library-only control loads it through a runtime probe but creates no host. Inspect round trips include scheduling, serialization and diagnostic work; not pure transport or input latency.';
    await output.writeAsString('${jsonEncode(report)}\n');
  }
}
