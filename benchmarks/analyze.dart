import 'dart:io';

import 'src/common.dart';

List<Json> analyze(String directory) {
  final results = <Json>[];
  for (final file in namedFiles(directory, 'run.json')) {
    final run = readJson(file.path) as Json;
    final base = <String, dynamic>{
      for (final key in ['implementation', 'workload', 'run_id']) key: run[key],
    };
    if (run['purpose'] != 'foreground measurement') {
      results.add({
        ...base,
        'status': 'excluded from performance: ${run['purpose']}',
        'correctness': run['correctness'],
        'equal_work_timing_eligible': false,
        'input_count': run['input_count'],
        'scheduled_inputs_missed': run['input_deadlines_missed'],
      });
      continue;
    }
    final folder = file.parent.path;
    final app = File('$folder/application.json').existsSync()
        ? readJson('$folder/application.json') as Json
        : null;
    final native = switch (run['implementation']) {
      'rust' => app,
      'dart' => app?['native'],
      _ => null,
    };
    final planned = run['seconds_requested'] == null
        ? null
        : number(run['seconds_requested']) * (rates[run['workload']] ?? 0);
    final excess = planned == null
        ? null
        : (number(run['input_count']) - planned).clamp(0, double.infinity);
    final uninjected = planned == null
        ? null
        : (planned - number(run['input_count'])).clamp(0, double.infinity);
    var frames = <Json>[];
    String? displayedColumn;
    if (File('$folder/present.csv').existsSync()) {
      final rows = readCsv('$folder/present.csv');
      if (rows.isNotEmpty) {
        for (final key in [
          'CPUStartQPC',
          'ProcessID',
          'MsBetweenPresents',
          'MsBetweenDisplayChange',
        ]) {
          if (!rows.first.containsKey(key)) {
            throw FormatException('PresentMon CSV is missing $key');
          }
        }
        displayedColumn = [
          'DisplayedTime',
          'MsUntilDisplayed',
        ].where(rows.first.containsKey).firstOrNull;
        if (displayedColumn == null) {
          throw FormatException(
            'PresentMon CSV is missing DisplayedTime or MsUntilDisplayed',
          );
        }
        frames = rows
            .where(
              (r) =>
                  number(r['ProcessID']) == run['process_id'] &&
                  number(r['CPUStartQPC']) >= number(run['start_qpc']) &&
                  number(r['CPUStartQPC']) < number(run['end_qpc']),
            )
            .toList();
        if (frames.map((r) => r['SwapChainAddress']).toSet().length > 1) {
          throw StateError(
            'Multiple swapchains require explicit selection before aggregation',
          );
        }
      }
    }
    final displayed = frames.where((r) => r[displayedColumn] != 'NA').toList();
    final response = File('$folder/input-analysis.json').existsSync()
        ? readJson('$folder/input-analysis.json')['response_presentation']
        : null;
    final correlated =
        response != null && number(response['frames_correlated']) > 0;
    final rate = rates[run['workload']] ?? 0;
    final target = rate == 0 ? null : 1000 / rate;
    final intervals = column(displayed.skip(1), 'MsBetweenDisplayChange');
    final samples = array(run['process_samples']);
    results.add({
      ...base,
      'correctness': run['correctness'],
      'equal_work_timing_eligible':
          planned != null &&
          excess == 0 &&
          uninjected == 0 &&
          run['input_deadlines_missed'] == 0 &&
          (run['correctness'] == null || at(run, 'correctness.passed') == true),
      'input_delivery': {
        'planned': planned,
        'injected': run['input_count'],
        'excess': excess,
        'uninjected': uninjected,
      },
      'status': frames.isEmpty
          ? 'presentation unavailable'
          : correlated
          ? 'ETW captured with response-frame correlation; parity review still required'
          : 'ETW captured; response-frame correlation and parity review still required',
      'scheduled_inputs_missed': run['input_deadlines_missed'],
      'input_count': run['input_count'],
      'duration_ms': run['duration_ms'],
      'delivery_quality': number(run['input_deadlines_missed']) > 0
          ? 'driver missed deadlines; exclude from matched-cadence ranking'
          : 'no skipped input deadlines; inspect recorded input jitter separately',
      'cpu_percent_one_core': run['cpu_percent_one_core'],
      'working_set_bytes': distribution(
        samples.map((s) => s['working_set_bytes']),
      ),
      'private_bytes': distribution(samples.map((s) => s['private_bytes'])),
      'window_available_ms': run['window_available_ms'],
      'application_work': app == null
          ? null
          : {
              'updates': app['updates'],
              'cells_written': app['cells_written'],
              'shell_view_builds': app['view_builds'],
              'shell_cell_builds': app['cell_builds'],
              'shell_visible_range': app['visible_range'],
              'solid_row_components_created': app['row_components_created'],
              'solid_mounted_window': app['mounted_window'],
              'solid_scroll_offset': app['scroll_offset'],
              'flutter_row_builds': app['row_builds'],
              'flutter_visible_rows': app['visible_rows'],
              'flutter_scroll_y': app['scroll_y'],
              'view': app['view'],
            },
      'native_diagnostics': native == null
          ? null
          : {
              'scope': app?['scope'],
              'draw': native['draw'],
              'dirty_to_present_submit': native['dirty_to_present_submit'],
              'input_to_frame': native['input_to_frame'],
              'limit': 'Cumulative native histories include startup and warmup; no changed-cell presentation correlation',
            },
      'solid_draw_overlay': run['implementation'] == 'solid'
          ? {'scope': app?['scope'], 'statistics': app?['draw_overlay']}
          : null,
      'flutter_frame_timing': run['implementation'] == 'flutter'
          ? {
              'scope': at(app, 'frames.scope'),
              'build_us': at(app, 'frames.build_us'),
              'raster_us': at(app, 'frames.raster_us'),
              'total_us': at(app, 'frames.total_us'),
              'limit': 'Flutter FrameTiming build and raster phases for every frame since startup; the estimator matches the process percentiles but the history is cumulative',
            }
          : null,
      'dart_publication': run['implementation'] == 'dart'
          ? {
              'scope': 'Dataset edits from delivered workload clicks, through the applied acknowledgement; initial upload reported separately',
              'statistics': app?['publication'],
              'limit': 'Application-defined percentile estimator; do not add stage percentiles or treat acknowledgement as presentation',
            }
          : null,
      'presentation': frames.isEmpty
          ? null
          : {
              'frames': frames.length,
              'frames_not_displayed': frames.length - displayed.length,
              'between_presents_ms': distribution(
                column(frames.skip(1), 'MsBetweenPresents'),
              ),
              'between_display_changes_ms': distribution(intervals),
              'estimated_missed_workload_slots':
                  target == null || intervals.isEmpty
                  ? null
                  : intervals.fold<num>(
                      0,
                      (sum, n) =>
                          sum +
                          (roundEven(n / target) - 1).clamp(0, double.infinity),
                    ),
              'target_period_ms': target,
              'input_associated_display_ms': distribution(
                column(displayed, 'MsAllInputToPhotonLatency'),
              ),
              'input_to_response_present_ms': correlated
                  ? response['input_to_response_present_ms']
                  : null,
              'input_to_response_display_ms': correlated
                  ? response['input_to_response_display_ms']
                  : null,
              'latency_limit': "ETW input association does not prove the frame contains the changed cell; the response figures come from the traced run's changed-frame correlation in input-analysis.json",
            },
    });
  }
  for (final file in namedFiles(directory, 'failure.json')) {
    if (File('${file.parent.path}/run.json').existsSync()) continue;
    final failure = readJson(file.path) as Json;
    results.add({
      for (final key in ['implementation', 'workload', 'run_id'])
        key: failure[key],
      'status': 'incomplete or legacy failed observation; retained for reliability accounting',
      'failure': failure,
      'equal_work_timing_eligible': false,
      'presentation': null,
    });
  }
  // PowerShell emitted a singleton object for one observation. Keep this shape
  // for existing consumers; readers accept either singleton or array.
  writeJson(
    '$directory/analysis.json',
    results.length == 1 ? results.single : results,
  );
  return results;
}

Future<void> main(List<String> args) => guarded(() async {
  final options = Options(args);
  final directory = options.string('directory');
  options.done();
  analyze(directory);
});
