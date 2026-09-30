import 'dart:async';
import 'dart:io';

import 'src/common.dart';
import 'src/process.dart';

const runFlags = {
  'capture-present',
  'background-smoke',
  'packaged',
  'trace-input',
  'no-pointer-warmup',
  'release-records',
  'flutter-isolate',
};

Json correctness(
  Json app, {
  required String implementation,
  required String workload,
  required int rows,
  required int inputCount,
}) {
  final issues = <String>[];
  final updates = ['cell', 'burst', 'view'].contains(workload) ? inputCount : 0;
  final cells =
      updates *
      (workload == 'burst'
          ? 8
          : workload == 'view'
          ? 0
          : 1);
  final price = rows == 0
      ? null
      : workload == 'view' || updates == 0
      ? '100.00'
      : 'Tick ${updates.toString().padLeft(6, '0')}';
  final stage = workload == 'view' ? inputCount % 4 : null;
  final nativePrice = implementation == 'dart'
      ? at(app, 'native_first_price.value')
      : implementation == 'rust'
      ? app['first_price']
      : null;
  if (app['updates'] != updates) {
    issues.add('${app['updates']} updates for $updates injected clicks');
  }
  if (app['cells_written'] != cells) {
    issues.add('Changed-cell count does not match injected input');
  }
  if (workload == 'view' && at(app, 'view.stage') != stage) {
    issues.add(
      'View stage ${at(app, 'view.stage')} after $inputCount clicks; expected $stage',
    );
  }
  if (app['first_price'] != price) {
    issues.add('Application final cell does not match injected input');
  }
  if (implementation == 'dart' && rows > 0 && nativePrice != price) {
    issues.add('Native final cell does not match injected input');
  }
  final visible = switch (implementation) {
    'rust' || 'flutter' => at(app, 'visible_rows.start'),
    'dart' => at(app, 'native.tables.table.visible_rows.start'),
    'shell' => array(app['visible_range']).firstOrNull,
    'solid' => at(app, 'mounted_window.start'),
    _ => null,
  };
  if (workload == 'scroll' && number(visible) <= 0) {
    issues.add('Scroll input did not advance the visible row window');
  }
  final scroll = scrollOffset(app, implementation),
      expectedScroll = workload == 'scroll' ? -78 * inputCount : 0;
  if (['rust', 'dart', 'solid', 'flutter'].contains(implementation) &&
      (scroll == null || (number(scroll) - expectedScroll).abs() > .01)) {
    issues.add(
      'Native scroll displacement does not match injected wheel input',
    );
  }
  if (implementation == 'shell' && number(app['cell_builds']) <= 0) {
    issues.add('Shell did not materialize any table cells');
  }
  return {
    'passed': issues.isEmpty,
    'issues': issues,
    'expected_updates': updates,
    'observed_updates': app['updates'],
    'expected_cells': cells,
    'observed_cells': app['cells_written'],
    'expected_price': price,
    'application_price': app['first_price'],
    'native_price': nativePrice,
    'expected_scroll_y': expectedScroll,
    'observed_scroll_y': scroll,
    'expected_view_stage': stage,
    'observed_view_stage': workload == 'view' ? at(app, 'view.stage') : null,
  };
}

dynamic scrollOffset(Json app, String implementation) =>
    switch (implementation) {
      'rust' || 'flutter' => app['scroll_y'],
      'dart' => at(app, 'native.tables.table.scroll_y'),
      'solid' =>
        array(app['scroll_offset']).length > 1 ? app['scroll_offset'][1] : null,
      _ => null,
    };

Future<int> runBenchmark(List<String> args) async {
  final o = Options(args, flags: runFlags);
  final implementation = o.string('implementation', 'dart'),
      workload = o.string('workload', 'idle'),
      runId = o.string('run-id', 'pilot');
  final seconds = o.integer('seconds', 10, 2, 120),
      rows = o.integer('rows', 100000, 0, 1000000);
  final capture = o.flag('capture-present'),
      background = o.flag('background-smoke'),
      packaged = o.flag('packaged'),
      trace = o.flag('trace-input'),
      noPointer = o.flag('no-pointer-warmup'),
      release = o.flag('release-records'),
      isolate = o.flag('flutter-isolate');
  o.done();
  if (!implementations.contains(implementation) ||
      !rates.containsKey(workload)) {
    throw ArgumentError('Unknown implementation or workload');
  }
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]*$').hasMatch(runId)) {
    throw ArgumentError('Run ID must be a single filename');
  }
  if (background && capture) {
    throw ArgumentError(
      'BackgroundSmoke cannot capture presentation measurements',
    );
  }
  if (trace &&
      (background || packaged || !['rust', 'dart'].contains(implementation))) {
    throw ArgumentError(
      'Input tracing requires an unpackaged foreground Rust or Dart fixture',
    );
  }
  if (release && implementation != 'dart') {
    throw ArgumentError('ReleaseRecords applies to the Dart fixture');
  }
  if (isolate && implementation != 'flutter') {
    throw ArgumentError('FlutterIsolate applies to the Flutter fixture');
  }
  if (rows != 100000 && !['idle', 'view'].contains(workload)) {
    throw ArgumentError(
      'Only the idle and view workloads run with a row count other than 100000',
    );
  }
  final root = repositoryRoot(),
      folder =
          '${repositoryRoot()}/reports/comparison/$runId/$implementation-$workload';
  for (final name in ['application.json', 'run.json', 'failure.json']) {
    if (File('$folder/$name').existsSync()) {
      throw StateError(
        'Attempt output already exists in $folder. Choose another RunId.',
      );
    }
  }
  if (trace &&
      implementation == 'dart' &&
      !File('$root/build/comparison-trace/gpuidart.dll').existsSync()) {
    throw StateError(
      'Input tracing needs the trace library from benchmarks/build_trace.dart',
    );
  }
  final driver = await driverExecutable();
  Directory(folder).createSync(recursive: true);
  final exe = fixtureExecutable(
    implementation,
    packaged: packaged,
    trace: trace,
  );
  final appOutput = '$folder/application.json';
  final library = packaged
      ? '$root/build/comparison/$implementation/gpuidart.dll'
      : trace
      ? '$root/build/comparison-trace/gpuidart.dll'
      : '$root/target/release/gpuidart.dll';
  final environment = <String, String>{};
  environment.addAll({
    'GPUIDART_LIBRARY': library,
    'GPUIDART_BENCH_ROWS': '$rows',
    'GPUIDART_BENCH_WORKLOAD': workload,
    'GPUIDART_BENCH_RETAIN': release ? '0' : '1',
    'GPUIDART_BENCH_FLUTTER_SORT': isolate ? 'isolate' : 'ui',
  });
  if ((capture || trace) && ['rust', 'dart'].contains(implementation)) {
    environment['GPUI_PRESENT_FEEDBACK'] = '$folder/present-feedback.csv';
  }
  if (trace) {
    environment.addAll({
      'GPUIDART_INPUT_TRACE': '1',
      'GPUIDART_NATIVE_TRACE': '$folder/native-input-trace.json',
    });
  }
  if (packaged) {
    final windows = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    environment.removeWhere((key, value) => key.toUpperCase() == 'PATH');
    environment['PATH'] = '$windows;$windows\\System32';
  }
  final delta = implementation == 'solid'
      ? -156
      : implementation == 'flutter'
      ? -117
      : -120;
  writeJson('$folder/driver-config.json', {
    'executable': exe,
    'arguments': [
      implementation == 'shell'
          ? (packaged
                ? '$root/build/comparison/shell'
                : '$root/benchmarks/shell')
          : appOutput,
    ],
    'folder': folder,
    'environment': environment,
    'workload': workload,
    'seconds': seconds,
    'background': background,
    'no_pointer_warmup': noPointer,
    'shell': implementation == 'shell',
    'wheel_delta': delta,
  });
  Process? present;
  Future<int>? presentExit;
  Future<void>? presentLogs;
  int? traceExit;
  var traceStatus = 'not requested';
  Json raw = {};
  try {
    if (capture) {
      present = await Process.start('$root/.tools/presentmon/PresentMon.exe', [
        '--output_file',
        '$folder/present.csv',
        '--qpc_time',
        '--timed',
        '${seconds + 25}',
        '--terminate_after_timed',
        '--no_console_stats',
        '--session_name',
        'gpuidart-${DateTime.now().microsecondsSinceEpoch}',
      ], workingDirectory: folder);
      presentExit = present.exitCode.then((code) {
        traceExit = code;
        return code;
      });
      presentLogs = Future.wait([
        present.stdout.pipe(File('$folder/present.stdout.log').openWrite()),
        present.stderr.pipe(File('$folder/present.stderr.log').openWrite()),
      ]).then((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 700));
      traceStatus = traceExit == null
          ? 'running; validate CSV after exit'
          : 'failed; see present.stderr.log';
    }
    final result = await execute(driver, [
      '--config',
      '$folder/driver-config.json',
    ], check: false);
    if (File('$folder/driver-result.json').existsSync()) {
      raw = readJson('$folder/driver-result.json') as Json;
    }
    if (result.exitCode != 0) {
      throw StateError(raw['error'] ?? '${result.stderr}');
    }
    if (implementation == 'shell') {
      final text =
          '${File('$folder/stdout.log').readAsStringSync()}\n${File('$folder/stderr.log').readAsStringSync()}';
      final matches = RegExp(r'BENCHMARK_RESULT (\{.*\})').allMatches(text);
      if (matches.isNotEmpty) {
        File(appOutput).writeAsStringSync(matches.last.group(1)!);
      }
    }
    if (!File(appOutput).existsSync()) {
      throw StateError('Application produced no verification report');
    }
    final app = readJson(appOutput) as Json;
    final verification = correctness(
      app,
      implementation: implementation,
      workload: workload,
      rows: rows,
      inputCount: number(raw['input_count']).toInt(),
    );
    if (presentExit != null && traceExit == null) {
      await presentExit.timeout(
        const Duration(seconds: 40),
        onTimeout: () => -1,
      );
    }
    if (capture && File('$folder/present.csv').existsSync()) {
      final captured = readCsv('$folder/present.csv'),
          kept = <Json>[],
          dropped = <String, int>{};
      for (final row in captured) {
        if (number(row['ProcessID']) == raw['process_id']) {
          kept.add(row);
        } else {
          final key = '${row['Application']}';
          dropped[key] = (dropped[key] ?? 0) + 1;
        }
      }
      if (kept.isNotEmpty) writeCsv('$folder/present.csv', kept);
      writeJson('$folder/present-filter.json', {
        'kept_process_id': raw['process_id'],
        'kept_rows': kept.length,
        'dropped_rows_by_application': dropped,
      });
    }
    final report = <String, dynamic>{
      ...raw,
      'implementation': implementation,
      'workload': workload,
      'run_id': runId,
      'packaged': packaged,
      'isolated_path': packaged,
      'purpose': trace
          ? 'foreground input tracing; ineligible for performance comparison'
          : background
          ? 'background fixture correctness; ineligible for performance comparison'
          : 'foreground measurement',
      'input_trace': trace,
      'pointer_warmup': !noPointer,
      'rows': rows,
      'seconds_requested': seconds,
      'release_records': release,
      'flutter_isolate': isolate,
      'driver_wait': 'one-millisecond high resolution waitable timer',
      'driver_warmup': !background,
      'correctness': verification,
      'wheel_delta': delta,
      'logical_processors': Platform.numberOfProcessors,
      'startup_boundary': 'process launch to created HWND; window explicitly shown afterward; not first displayed frame',
      'first_content_boundary': 'process launch to the first PrintWindow capture after showing the window whose client area holds more than one color, polled every 5 ms; composited content, not the swap chain present',
      'application_first_frame_ms': app['first_frame_ms_since_launch'],
      'application_first_frame_boundary': "the fixture's own clock: Dart when open returns with the window up and the first description applied; Flutter at the first FrameTiming callback; both relative to the launch instant the runner passed in",
      'trace_status': traceStatus,
      'trace_exit_code': traceExit,
      'exe_sha256': (await hash(exe)).toUpperCase(),
      'native_library_sha256': implementation == 'dart'
          ? (await hash(library)).toUpperCase()
          : null,
      'driver_sha256': (await hash(driver)).toUpperCase(),
      'runner_sha256': (await hash('$root/benchmarks/run.dart')).toUpperCase(),
    };
    writeJson('$folder/run.json', report);
    stdout.writeln(
      '${verification['passed'] == true ? 'Verified' : 'Correctness failure retained for'} $implementation $workload: ${raw['input_count']} inputs. $folder',
    );
    return verification['passed'] == true ? 0 : 2;
  } catch (error) {
    writeJson('$folder/failure.json', {
      'implementation': implementation,
      'workload': workload,
      'run_id': runId,
      'status': 'interrupted observation; retain for reliability accounting',
      'error': '$error',
      'failed_at_utc': DateTime.now().toUtc().toIso8601String(),
      'inputs': raw['inputs'],
      'scheduled_inputs_missed': raw['input_deadlines_missed'],
      'process_samples': raw['process_samples'],
    });
    rethrow;
  } finally {
    if (present != null && traceExit == null) present.kill();
    if (presentLogs != null) await presentLogs;
    // The config carries the child environment. Keep reports free of unrelated
    // environment values after the native process has consumed it.
    File('$folder/driver-config.json').deleteSync();
  }
}

Future<void> main(List<String> args) => guarded(() async {
  exitCode = await runBenchmark(args);
});
