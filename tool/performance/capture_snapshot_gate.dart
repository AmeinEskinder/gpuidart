import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/runtime_info.dart';
import 'package:gpuidart/tracing.dart';

import 'snapshot_fixture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError(
      'Usage: capture_snapshot_gate.dart NEW_OUTPUT_DIRECTORY FIELDS',
    );
  }
  final output = Directory(args[0]);
  if (output.existsSync()) throw StateError('Retain earlier gate attempt');
  output.createSync(recursive: true);
  final fixture = SnapshotFixture(int.parse(args[1]));
  final trace = GpuiTrace(capacity: 8192);
  final samples = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'passed': false,
    'fields': fixture.fields,
    'mode': const bool.fromEnvironment('gpuidart.packaged') ? 'aot' : 'jit',
    'samples': samples,
    'scope': 'Synthetic property-inspector stress workload. Fresh whole descriptions on every publish, including unchanged values; no identity shortcut. Dataset messages excluded from ordinary updates. CPU content paint and native draw histograms, no presentation or input latency claims.',
  };
  GpuiHost? host;
  try {
    host = await GpuiHost.openView(
      fixture.build,
      datasets: [SnapshotFixture.dataset()],
      trace: trace,
      window: const GpuiWindowOptions(
        title: 'Snapshot-heavy gate',
        width: 960,
        height: 640,
      ),
    );
    await host.diagnose('prepare', {
      'input': 'retained-input',
      'text': 'retained selection',
      'start': 1,
      'end': 7,
      'table': 'retained-table',
      'row': 800,
    });
    final before = await host.diagnose('inspect');
    report['before'] = before;
    report['memory_before'] = {
      'application': readRuntimeInfo(),
      'ui': await host.diagnose('runtime'),
    };
    for (final operation in [
      'unchanged',
      'property',
      'reorder',
      'insert',
      'remove',
    ]) {
      for (var i = 0; i < 8; i++) {
        fixture.change(operation);
        final bytesBefore = host.metrics.encodedBytes;
        await host.rebuild();
        final state = await host.diagnose('repaint', {'frames': 1});
        final inputBefore = (before['inputs'] as Map)['retained-input'] as Map;
        final inputNow = (state['inputs'] as Map)['retained-input'] as Map;
        final tableBefore = (before['tables'] as Map)['retained-table'] as Map;
        final tableNow = (state['tables'] as Map)['retained-table'] as Map;
        final preserved =
            jsonEncode(inputBefore) == jsonEncode(inputNow) &&
            tableBefore['entity'] == tableNow['entity'] &&
            tableBefore['scroll_y'] == tableNow['scroll_y'] &&
            jsonEncode(tableBefore['selection']) ==
                jsonEncode(tableNow['selection']);
        samples.add({
          'operation': operation,
          'index': i,
          'revision': state['revision'],
          'bytes': host.metrics.encodedBytes - bytesBefore,
          'retained_state_preserved': preserved,
          'draw': state['draw'],
          'native': state['native'],
        });
        if (!preserved) {
          throw StateError('Retained state changed during $operation');
        }
        final labels = state['labels'] as Map;
        for (var field = 0; field < fixture.fields; field++) {
          if (labels['field-$field'] !=
              'Device ${field ~/ 32} / property $field: ${fixture.values[field]}') {
            throw StateError('Description value mismatch');
          }
        }
      }
    }
    if (host.metrics.dataMessages != 0 || host.metrics.encodedSnapshots != 40) {
      throw StateError('Snapshot workload did not isolate 40 replacements');
    }
    report['memory_after'] = {
      'application': readRuntimeInfo(),
      'ui': await host.diagnose('runtime'),
    };
    report['metrics'] = host.metrics.read();
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
    final capture = trace.toJson();
    if ((capture['metadata'] as Map)['capture_complete'] != true) {
      report['passed'] = false;
      report['trace_error'] = 'Incomplete capture';
      exitCode = 1;
    }
    await File('${output.path}/trace.json').writeAsString(jsonEncode(capture));
    await File('${output.path}/report.json').writeAsString(jsonEncode(report));
  }
  stdout.writeln('Snapshot gate ${fixture.fields}: passed=${report['passed']}');
}
