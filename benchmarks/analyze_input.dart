import 'dart:io';

import 'src/common.dart';

Json analyzeInput(String directory) {
  final run = readJson(
    '$directory/${File('$directory/run.json').existsSync() ? 'run' : 'failure'}.json',
  ) as Json;
  final native = array(readJson('$directory/native-input-trace.json'))
      .cast<Json>();
  final applicationPath = '$directory/application.json.input-trace.json';
  final app =
      run['implementation'] == 'dart' && File(applicationPath).existsSync()
      ? array(readJson(applicationPath)).cast<Json>()
      : run['implementation'] == 'rust'
      ? native
      : <Json>[];
  Map<String, List<Json>> index(List<Json> events) {
    final result = <String, List<Json>>{};
    for (final e in events) {
      if (e['sequence'] != null) {
        (result['${e['sequence']}/${e['stage']}'] ??= []).add(e);
      }
    }
    return result;
  }

  final ni = index(native), ai = index(app);
  final painted =
      native
          .where((e) => e['stage'] == 'content_painted' && e['qpc'] != null)
          .toList()
        ..sort((a, b) => number(a['qpc']).compareTo(number(b['qpc'])));
  final presents =
      File('$directory/present.csv').existsSync() && run['process_id'] != null
      ? readCsv('$directory/present.csv')
            .where((e) => number(e['ProcessID']) == run['process_id'])
            .toList()
      : <Json>[];
  presents.sort(
    (a, b) => number(a['CPUStartQPC']).compareTo(number(b['CPUStartQPC'])),
  );
  final revisions = <String, Json>{
    for (final e in native)
      if (e['stage'] == 'update_applied' && at(e, 'data.revision') != null)
        '${at(e, 'data.revision')}': e,
  };
  final observations = <Json>[];
  for (final input in array(run['inputs'])) {
    final seq = input['sequence'];
    final down = ni['$seq/gpui_mouse_down'] ?? [],
        up = ni['$seq/gpui_mouse_up'] ?? [],
        click = ni['$seq/native_click_handler'] ?? [];
    final handler = ai['$seq/application_handler'] ?? [],
        observed = ai['$seq/state_observed'] ?? [],
        ack = ai['$seq/applied_acknowledged'] ?? [];
    final revisionEvent = handler.length == 1
        ? revisions['${at(handler.single, 'data.target_revision')}']
        : null;
    final applied = run['implementation'] == 'rust'
        ? ni['$seq/update_applied'] ?? []
        : revisionEvent == null
        ? <Json>[]
        : [revisionEvent];
    Json? paint, present;
    num? presentMs, displayMs;
    if (applied.length == 1 && applied.single['qpc'] != null) {
      final revision = at(applied.single, 'data.revision');
      paint = painted
          .where(
            (e) =>
                number(e['qpc']) >= number(applied.single['qpc']) &&
                (revision == null || at(e, 'data.revision') == revision),
          )
          .firstOrNull;
      if (paint != null) {
        present = presents
            .where((e) => number(e['CPUStartQPC']) >= number(paint!['qpc']))
            .firstOrNull;
        if (present != null &&
            input['qpc'] != null &&
            number(run['qpc_frequency']) > 0) {
          presentMs = roundEven(
            (number(present['CPUStartQPC']) - number(input['qpc'])) *
                1000 /
                number(run['qpc_frequency']),
            3,
          );
          final key = [
            'DisplayLatency',
            'MsUntilDisplayed',
          ].where(present.containsKey).firstOrNull;
          if (key != null && present[key] != 'NA') {
            displayMs = roundEven(presentMs + number(present[key]), 3);
          }
        }
      }
    }
    final expected = handler.length == 1
        ? 'Tick ${number(at(handler.single, 'data.update_ordinal')).toInt().toString().padLeft(6, '0')}'
        : null;
    var matches =
        observed.length == 1 && at(observed.single, 'data.value') == expected;
    if (run['implementation'] == 'dart') {
      matches = matches && at(observed.single, 'data.native.value') == expected;
    }
    final gap = input['packets_accepted'] != 2
        ? 'injection acceptance unverified'
        : down.length != 1
        ? 'injection to GPUI mouse down'
        : up.length != 1
        ? 'mouse down to GPUI mouse up'
        : click.length != 1
        ? 'GPUI mouse events to native click handler'
        : handler.length != 1
        ? 'native click handler to application handler'
        : applied.length != 1
        ? 'application handler to native application of update'
        : run['implementation'] == 'dart' && ack.length != 1
        ? 'native application of update to Dart acknowledgement'
        : !matches
        ? 'applied update to expected state readback'
        : null;
    observations.add({
      'sequence': seq,
      'packets_accepted': input['packets_accepted'],
      'mouse_down': down.length,
      'mouse_up': up.length,
      'native_click_handler': click.length,
      'application_handler': handler.length,
      'native_update_applied': applied.length,
      'dart_acknowledged': ack.length,
      'state_observed': observed.length,
      'state_matches': matches,
      'first_gap': gap,
      'mouse_down_positions': down.isEmpty
          ? [null]
          : down.map((e) => e['data']).toList(),
      'mouse_up_positions': up.isEmpty
          ? [null]
          : up.map((e) => e['data']).toList(),
      'content_painted': paint == null ? 0 : 1,
      'response_present_qpc': present == null
          ? null
          : number(present['CPUStartQPC']),
      'input_to_response_present_ms': presentMs,
      'input_to_response_display_ms': displayMs,
    });
  }
  Json? summary(String key) {
    final values = observations.map((o) => o[key]).whereType<num>().toList()
      ..sort();
    return values.isEmpty
        ? null
        : {
            'count': values.length,
            'min': values.first,
            'median': values[(values.length - 1) ~/ 2],
            'max': values.last,
          };
  }

  final result = <String, dynamic>{
    for (final key in ['implementation', 'workload', 'run_id']) key: run[key],
    'inputs': observations.length,
    'complete_chains': observations.where((o) => o['first_gap'] == null).length,
    'gaps': observations.where((o) => o['first_gap'] != null).toList(),
    'observations': observations,
    'response_presentation': {
      'frames_correlated': observations
          .where((o) => o['input_to_response_present_ms'] != null)
          .length,
      'input_to_response_present_ms': summary('input_to_response_present_ms'),
      'input_to_response_display_ms': summary('input_to_response_display_ms'),
      'limit': 'Present start is the first PresentMon record after the first content paint of the applied update; display adds PresentMon DisplayLatency. Requires a present.csv capture and content_painted trace events; diagnostic builds only.',
    },
    'limit': 'Diagnostic builds and per-update readbacks; ineligible for performance comparison. A missing GPUI event does not by itself establish driver fault. QPC and Dart elapsed times are not presentation timestamps; response_presentation carries the PresentMon-correlated ones.',
  };
  writeJson('$directory/input-analysis.json', result);
  stdout.writeln(
    '${run['implementation']} ${run['workload']}: ${result['complete_chains']}/${result['inputs']} complete traced chains; ${(result['gaps'] as List).length} gaps.',
  );
  return result;
}

Future<void> main(List<String> args) => guarded(() async {
  final o = Options(args);
  final dir = o.string('directory');
  o.done();
  analyzeInput(dir);
});
