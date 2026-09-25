import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';
import 'package:gpuidart/src/trace_clock.dart';
import 'package:gpuidart/tracing.dart';

Future<void> main(List<String> args) async {
  final clock = TraceClock();
  final mainTick = clock.now().$1;
  final trace = GpuiTrace(capacity: 512);
  final stages = <String, int>{'dart_main': mainTick};
  final dataset = TableDataset(
    'records',
    columns: ['ID', 'Value'],
    rows: List.generate(100000, (i) => ['$i', 'Row $i']),
  );
  stages['records_constructed'] = clock.now().$1;
  final host = await GpuiHost.openView(
    () => UiColumn('root', [
      const UiText('title', '100,000-record startup and idle fixture'),
      const UiTable('table', dataset: 'records'),
    ]),
    datasets: [dataset],
    trace: trace,
  );
  stages['host_ready'] = clock.now().$1;
  Future<Map<String, dynamic>> processes() async {
    final ui = await host.diagnose('runtime');
    final app = readRuntimeInfo();
    return {
      'roles': {'application': app['pid'], 'ui': ui['pid']},
      'by_pid': {'${ui['pid']}': ui, '${app['pid']}': app},
    };
  }

  late Map<String, dynamic> state, before, after;
  late int idleStart, idleEnd;
  try {
    state = await host.diagnose('repaint', {'frames': 2});
    stages['verified_draw_ack'] = clock.now().$1;
    before = await processes();
    idleStart = clock.now().$1;
    await Future<void>.delayed(const Duration(seconds: 2));
    idleEnd = clock.now().$1;
    after = await processes();
  } finally {
    await host.close();
  }
  final capture = trace.toJson();
  if ((capture['metadata'] as Map)['capture_complete'] != true) {
    throw StateError('Incomplete baseline trace');
  }
  stdout.writeln(
    jsonEncode({
      'passed': true,
      'mode': const bool.fromEnvironment('gpuidart.packaged') ? 'aot' : 'jit',
      'clock': clock.name,
      'frequency': clock.frequency,
      'stages': stages,
      'idle_start': idleStart,
      'idle_end': idleEnd,
      'before_idle': before,
      'after_idle': after,
      'window': state['window'],
      'native': state['native'],
      'trace': capture,
      'scope': 'Instrumented release-native 100k startup/idle fixture. Draw acknowledgement follows an explicit repaint request; it is not first useful display or presentation. CPU sampling includes diagnostic overhead. Process RSS values must not be summed as unique memory.',
    }),
  );
}
