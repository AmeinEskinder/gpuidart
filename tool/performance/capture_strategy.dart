import 'dart:convert';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import 'experiment_diff.dart';
import 'experiment_transport.dart';
import 'snapshot_fixture.dart';

Future<void> main(List<String> args) async {
  if (args.length != 5) {
    throw ArgumentError(
      'Usage: capture_strategy.dart NEW_OUTPUT_DIRECTORY BINARY LAUNCHER snapshot|subviews|patches FIELDS',
    );
  }
  final output = Directory(args[0]);
  if (output.existsSync()) {
    throw StateError('Retain earlier experiment attempt');
  }
  output.createSync(recursive: true);
  final strategy = args[3];
  if (!['snapshot', 'subviews', 'patches'].contains(strategy)) {
    throw ArgumentError('Unknown strategy');
  }
  final fixture = SnapshotFixture(int.parse(args[4]), fixedParts: true);
  final data = SnapshotFixture.dataset();
  var root = fixture.build().toJson();
  var revision = 1, request = 0;
  final samples = <Object?>[];
  final checks = <Object?>[];
  final report = <String, Object?>{
    'passed': false,
    'strategy': strategy,
    'fields': fixture.fields,
    'mode': const bool.fromEnvironment('gpuidart.packaged') ? 'aot' : 'jit',
    'samples': samples,
    'correctness': checks,
    'scope': 'Experimental framed process transport common to all strategies, not production FFI. Fixed part bounds; real GPUI controls/materializer. Native staging clones and full-tree validation remain measured. No presentation or input-latency claim.',
  };
  ExperimentTransport? peer;
  try {
    peer = await ExperimentTransport.start(
      File(args[1]).absolute.path,
      File(args[2]).absolute.path,
    );
    final setup = await peer.send({
      'strategy': strategy,
      'initial': {
        'snapshot': {'revision': revision, 'root': root},
        'datasets': [
          {
            'id': data.id,
            'revision': 1,
            'data': {
              'columns': data.columns,
              'rows': List.generate(data.rowCount, data.row),
              'ids': List.generate(data.rowCount, data.rowId),
            },
          },
        ],
        'window': {
          'title': 'Snapshot strategy experiment',
          'width': 960,
          'height': 640,
        },
      },
    });
    ensure(setup['ready'] == true, 'No native readiness');
    ensure(
      (await peer.send({'kind': 'prepare', 'request': ++request}))['passed'] ==
          true,
      'Preparation failed',
    );
    var before = await peer.send({'kind': 'inspect', 'request': ++request});
    report['before'] = before;
    report['dart_memory_before'] = dartMemory();
    Map previousParts = before['state']['part_materializations'] as Map? ?? {};
    ensure(
      ((before['state'] as Map)['tables']['retained-table']['scroll_y']
              as num) <
          0,
      'Table did not scroll',
    );
    for (final operation in [
      'unchanged',
      'property',
      'reorder',
      'insert',
      'remove',
    ]) {
      for (var iteration = 0; iteration < 8; iteration++) {
        final group = fixture.edit % fixture.fields ~/ 32;
        final removed = fixture.extras.isEmpty ? null : fixture.extras.last;
        fixture.change(operation);
        var visited = 0;
        final build = Stopwatch()..start();
        UiNode? built;
        if (strategy != 'subviews') {
          built = fixture.build();
        } else if (operation == 'property') {
          built = fixture.section(group);
        } else if (operation == 'insert') {
          final id = fixture.extras.last;
          built = UiText(
            'extra-$id',
            'Inserted $id',
            style: const UiStyle(height: UiSize.px(24)),
          );
        }
        final buildUs = build.elapsedMicroseconds;
        final describe = Stopwatch()..start();
        final wire = built?.toJson();
        final describeUs = describe.elapsedMicroseconds;
        final diff = Stopwatch()..start();
        late Map<String, Object?> change;
        if (strategy == 'snapshot') {
          root = wire!;
          change = {'strategy': strategy, 'root': root};
        } else if (strategy == 'patches') {
          final result = diffDescriptions(root, wire!);
          visited = result.visited;
          root = wire;
          change = {'strategy': strategy, 'ops': result.ops};
        } else {
          final parts = (root['children'] as List).cast<Map>();
          List<String>? order;
          if (operation == 'property') {
            parts[parts.indexWhere((p) => p['id'] == 'section-$group')] = wire!;
          }
          if (operation == 'insert') parts.add(wire!);
          if (operation == 'remove') {
            parts.removeWhere((p) => p['id'] == 'extra-$removed');
          }
          if (operation == 'reorder') {
            order = [
              'retained-input',
              'retained-table',
              for (final g in fixture.order) 'section-$g',
              for (final id in fixture.extras) 'extra-$id',
            ];
            final byId = {for (final p in parts) p['id']: p};
            parts
              ..clear()
              ..addAll(order.map((id) => byId[id]!));
          }
          change = {
            'strategy': strategy,
            'replacements': [?wire],
            'removed': [if (operation == 'remove') 'extra-$removed'],
            'order': order,
          };
        }
        final diffUs = diff.elapsedMicroseconds;
        final result = await peer.send({
          'kind': 'update',
          'request': ++request,
          'base': revision,
          'revision': revision + 1,
          'change': change,
        });
        ensure(result['passed'] == true, 'Update failed: ${result['error']}');
        ensure(
          result['bytes'] == result['dart_transport']['bytes'],
          'Transferred byte count mismatch',
        );
        revision++;
        ensure(
          (result['state'] as Map)['revision'] == revision,
          'Revision mismatch',
        );
        ensure(
          result['state']['frame']['revision'] == revision,
          'Acknowledgement did not observe this revision painted',
        );
        final parts = result['state']['part_materializations'] as Map? ?? {};
        final rebuiltParts = [
          for (final id in parts.keys)
            if (parts[id] != previousParts[id]) id,
        ];
        if (strategy == 'subviews' && operation == 'property') {
          ensure(
            rebuiltParts.contains('section-$group'),
            'Changed subview did not render',
          );
          ensure(
            !rebuiltParts.any(
              (id) => '$id'.startsWith('section-') && id != 'section-$group',
            ),
            'Unchanged property subview rebuilt',
          );
        }
        previousParts = parts;
        checkRetained(before['state'] as Map, result['state'] as Map);
        final labels = (result['state'] as Map)['labels'] as Map;
        for (var field = 0; field < fixture.fields; field++) {
          ensure(
            labels['field-$field'] ==
                'Device ${field ~/ 32} / property $field: ${fixture.values[field]}',
            'Property mismatch',
          );
        }
        samples.add({
          'operation': operation,
          'index': iteration,
          'revision': revision,
          'build_us': buildUs,
          'describe_us': describeUs,
          'diff_us': diffUs,
          'diff_nodes_visited': visited,
          'transport': result['dart_transport'],
          'native_decode_us': result['decode_us'],
          'native_stages': result['stages'],
          'frame': result['state']['frame'],
          'native': result['state']['native'],
          'retained_state_preserved': true,
          'rebuilt_parts': rebuiltParts,
        });
      }
    }
    report['after_workload'] = await peer.send({
      'kind': 'inspect',
      'request': ++request,
    });
    report['dart_memory_after'] = dartMemory();

    Future<void> reject(String label, Map<String, Object?> message) async {
      final result = await peer!.send({
        ...message,
        'kind': 'update',
        'request': ++request,
      });
      ensure(result['passed'] == false, 'Invalid transaction accepted: $label');
      ensure(
        result['state']['revision'] == revision,
        'Rejected update advanced revision',
      );
      checkRetained(before['state'] as Map, result['state'] as Map);
      ensure(
        jsonEncode(result['state']['labels']) ==
            jsonEncode((report['after_workload'] as Map)['state']['labels']),
        'Rejected transaction changed labels',
      );
      checks.add({'case': label, 'passed': true, 'rejection': result['error']});
    }

    await reject('stale revision', {
      'base': 0,
      'revision': revision + 1,
      'resync': false,
      'change': {'strategy': 'snapshot', 'root': root},
    });
    final duplicate = jsonDecode(jsonEncode(root)) as Map;
    (duplicate['children'] as List).add((duplicate['children'] as List).first);
    await reject('duplicate ID resync rollback', {
      'base': revision,
      'revision': revision + 1,
      'resync': true,
      'change': {'strategy': 'snapshot', 'root': duplicate},
    });
    if (strategy == 'patches') {
      await reject('valid edit followed by invalid remove rolls back', {
        'base': revision,
        'revision': revision + 1,
        'change': {
          'strategy': 'patches',
          'ops': [
            {'op': 'text', 'id': 'field-0', 'text': 'must roll back'},
            {'op': 'remove', 'id': 'missing'},
          ],
        },
      });
    }
    if (strategy == 'subviews') {
      await reject('invalid subview order rolls back', {
        'base': revision,
        'revision': revision + 1,
        'change': {
          'strategy': 'subviews',
          'replacements': [],
          'removed': [],
          'order': ['missing'],
        },
      });
    }
    Future<Map<String, dynamic>> resync(Map<String, Object?> tree) async {
      final result = await peer!.send({
        'kind': 'update',
        'request': ++request,
        'base': 0,
        'revision': revision + 1,
        'resync': true,
        'change': {'strategy': 'snapshot', 'root': tree},
      });
      ensure(result['passed'] == true, 'Resync failed: ${result['error']}');
      revision++;
      return result;
    }

    final restored = await resync(root);
    checkRetained(before['state'] as Map, restored['state'] as Map);
    checks.add({'case': 'explicit resync preserves state', 'passed': true});
    final without = jsonDecode(jsonEncode(root)) as Map<String, Object?>;
    (without['children'] as List).removeWhere(
      (n) => n['id'] == 'retained-input',
    );
    final deleted = await resync(without);
    ensure(
      !(deleted['state']['inputs'] as Map).containsKey('retained-input'),
      'Removed input stayed mounted',
    );
    final readded = await resync(root);
    ensure(
      readded['state']['inputs']['retained-input']['entity'] !=
          before['state']['inputs']['retained-input']['entity'],
      'Remount reused disposed entity',
    );
    ensure(
      readded['state']['inputs']['retained-input']['text'] == '',
      'Remount retained stale text',
    );
    checks.add({'case': 'remove/reuse ID creates fresh state', 'passed': true});
    await peer.send({'kind': 'prepare', 'request': ++request});
    before = await peer.send({'kind': 'inspect', 'request': ++request});
    final moved = jsonDecode(jsonEncode(root)) as Map<String, Object?>;
    final children = moved['children'] as List;
    final input = children.removeAt(0);
    ((children.firstWhere((node) => node['id'] == 'section-0')
                as Map)['children']
            as List)
        .insert(0, input);
    final movedResult = await peer.send({
      'kind': 'update',
      'request': ++request,
      'base': revision,
      'revision': revision + 1,
      'resync': true,
      'change': {'strategy': 'snapshot', 'root': moved},
    });
    if (strategy == 'subviews') {
      ensure(
        movedResult['passed'] == false &&
            '${movedResult['error']}'.contains('reparenting'),
        'Expected explicit subview migration rejection',
      );
      checkRetained(before['state'] as Map, movedResult['state'] as Map);
      checks.add({
        'case': 'control reparenting',
        'passed': true,
        'limitation': 'rejected; state migration not implemented',
      });
    } else {
      ensure(movedResult['passed'] == true, 'Control reparent failed');
      checkRetained(
        before['state'] as Map,
        movedResult['state'] as Map,
        scroll: false,
      );
      checks.add({
        'case': 'control reparenting preserves entity/text/selection',
        'passed': true,
      });
    }
    report['final'] = await peer.send({'kind': 'close', 'request': ++request});
    report['native_exit_code'] = await peer.process.process.exitCode.timeout(
      const Duration(seconds: 10),
    );
    ensure(
      report['native_exit_code'] == 0,
      'Native process failed during shutdown',
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    await peer?.stop();
    await File('${output.path}/native.stderr.log')
        .writeAsString(await peer?.errors ?? '');
    await File('${output.path}/report.json').writeAsString(jsonEncode(report));
  }
  stdout.writeln('$strategy/${fixture.fields}: passed=${report['passed']}');
}

Map<String, Object> dartMemory() => {
  'pid': pid,
  'rss_bytes': ProcessInfo.currentRss,
  'peak_rss_bytes': ProcessInfo.maxRss,
  'scope': 'Dart driver process including fixture, mirror/diff state and measurement records; not a Dart heap census',
};

void ensure(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void checkRetained(Map before, Map after, {bool scroll = true}) {
  final input = before['inputs']['retained-input'] as Map;
  final current = after['inputs']['retained-input'] as Map;
  for (final key in ['entity', 'text', 'selection', 'focused']) {
    ensure(
      jsonEncode(input[key]) == jsonEncode(current[key]),
      'Retained input $key changed',
    );
  }
  final table = before['tables']['retained-table'] as Map;
  final next = after['tables']['retained-table'] as Map;
  for (final key in ['entity', 'selection', if (scroll) 'scroll_y']) {
    ensure(
      jsonEncode(table[key]) == jsonEncode(next[key]),
      'Retained table $key changed',
    );
  }
}
