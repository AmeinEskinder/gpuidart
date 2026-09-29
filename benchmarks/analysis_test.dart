import 'dart:io';

import 'package:test/test.dart';

import 'analyze.dart';
import 'analyze_input.dart';
import 'run.dart';
import 'resume_series.dart' show seriesDirectories;
import 'summarize_pair.dart';
import 'report_pair.dart';
import 'src/common.dart';

void main() {
  late Directory temp;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('gpuidart-benchmark-test-');
  });
  tearDown(() {
    temp.deleteSync(recursive: true);
  });
  String path(String name) => '${temp.path}/$name';
  Json run({String impl = 'synthetic-test', String workload = 'scroll'}) => {
    'purpose': 'foreground measurement',
    'implementation': impl,
    'workload': workload,
    'process_id': 42,
    'start_qpc': 100,
    'end_qpc': 200,
    'input_deadlines_missed': 0,
    'cpu_percent_one_core': 1,
    'window_available_ms': 2,
    'process_samples': [
      {'working_set_bytes': 100, 'private_bytes': 200},
    ],
  };
  const csv =
      'CPUStartQPC,ProcessID,SwapChainAddress,DisplayedTime,MsBetweenPresents,MsBetweenDisplayChange,MsAllInputToPhotonLatency\n90,42,1,16,1000,1000,1000\n110,42,1,16,1000,1000,10\n120,42,1,NA,10,NA,NA\n140,42,1,16,20,30,12\n160,42,1,16,20,20,11\n170,99,2,16,500,500,500\n210,42,1,16,500,500,500\n';
  test('filters process/time boundaries and excludes pre-window intervals', () {
    writeJson(path('run.json'), run());
    File(path('present.csv')).writeAsStringSync(csv);
    final result = analyze(temp.path).single;
    expect(at(result, 'presentation.frames'), 4);
    expect(at(result, 'presentation.frames_not_displayed'), 1);
    expect(at(result, 'presentation.between_display_changes_ms.p95'), 30);
    expect(at(result, 'presentation.between_presents_ms.samples'), 3);
    expect(at(result, 'presentation.input_to_response_present_ms'), isNull);
    expect(result['equal_work_timing_eligible'], isFalse);
  });
  test('accepts PresentMon 2.6 display column and rejects ambiguous/missing columns', () {
    writeJson(path('run.json'), run());
    File(path('present.csv'))
        .writeAsStringSync(csv.replaceAll('DisplayedTime', 'MsUntilDisplayed'));
    expect(
      at(analyze(temp.path).single, 'presentation.frames_not_displayed'),
      1,
    );
    File(path('present.csv'))
        .writeAsStringSync(csv.replaceFirst('140,42,1', '140,42,2'));
    expect(() => analyze(temp.path), throwsStateError);
    for (final key in [
      'CPUStartQPC',
      'ProcessID',
      'MsBetweenPresents',
      'MsBetweenDisplayChange',
      'DisplayedTime',
    ]) {
      File(path('present.csv'))
          .writeAsStringSync(csv.replaceFirst(key, 'missing'));
      expect(() => analyze(temp.path), throwsFormatException, reason: key);
    }
  });
  test('keeps incorrect work, extra inputs, missing cadence, interruptions, and background runs', () {
    writeJson(path('lost/run.json'), {
      ...run(impl: 'lost-update', workload: 'cell'),
      'input_count': 50,
      'cpu_percent_one_core': 2,
      'correctness': {
        'passed': false,
        'expected_updates': 50,
        'observed_updates': 49,
      },
    });
    writeJson(path('interrupted/failure.json'), {
      'implementation': 'interrupted',
      'workload': 'cell',
      'error': 'focus lost',
    });
    writeJson(path('extra/run.json'), {
      ...run(impl: 'extra-input', workload: 'cell'),
      'seconds_requested': 10,
      'input_count': 51,
      'correctness': {'passed': true},
      'process_samples': [],
    });
    writeJson(path('background/run.json'), {
      ...run(impl: 'background'),
      'purpose': 'background fixture correctness; ineligible for performance comparison',
    });
    writeJson(path('lost/failure.json'), {'implementation': 'duplicate'});
    final results = {
      for (final r in analyze(temp.path)) r['implementation']: r,
    };
    expect(results.length, 4);
    expect(at(results['lost-update'], 'correctness.observed_updates'), 49);
    expect(results['lost-update']!['cpu_percent_one_core'], 2);
    expect(
      results.values.every((r) => r['equal_work_timing_eligible'] == false),
      isTrue,
    );
    expect(at(results['extra-input'], 'input_delivery.excess'), 1);
    expect(at(results['extra-input'], 'correctness.passed'), isTrue);
  });
  test('nearest-rank percentiles, ties-to-even rounding, and CSV quoting stay stable', () {
    expect(distribution([4, 1, 3, 2]), {
      'samples': 4,
      'p50': 2,
      'p95': 4,
      'p99': 4,
      'max': 4,
    });
    expect(roundEven(2.5), 2);
    expect(roundEven(3.5), 4);
    expect(distribution([]), isNull);
    File(path('quoted.csv')).writeAsStringSync('a,b\r\n"x,y","a""b\nc"\r\n');
    expect(readCsv(path('quoted.csv')), [
      {'a': 'x,y', 'b': 'a"b\nc'},
    ]);
  });
  test('correlates the first paint after apply and present after paint for the same process', () {
    final inputs = [
      for (var s = 1; s <= 4; s++)
        {'sequence': s, 'packets_accepted': 2, 'qpc': 1000000 * s},
    ];
    writeJson(path('run.json'), {
      'implementation': 'rust',
      'workload': 'cell',
      'run_id': 'synthetic',
      'inputs': inputs,
      'process_id': 42,
      'qpc_frequency': 10000000,
    });
    final events = <Json>[];
    for (var s = 1; s <= 4; s++) {
      final base = 1000000 * s;
      for (final stage in ['gpui_mouse_down', 'gpui_mouse_up']) {
        events.add({
          'sequence': s,
          'stage': stage,
          'qpc': base + 1000,
          'data': {},
        });
      }
      if (s == 2) continue;
      events.addAll([
        {
          'sequence': s,
          'stage': 'native_click_handler',
          'qpc': base + 2000,
          'data': {},
        },
        {
          'sequence': s,
          'stage': 'application_handler',
          'qpc': base + 3000,
          'data': {'update_ordinal': s},
        },
      ]);
      if (s == 3) continue;
      events.addAll([
        {
          'sequence': s,
          'stage': 'update_applied',
          'qpc': base + 4000,
          'data': {'updates': s},
        },
        {
          'sequence': null,
          'stage': 'content_painted',
          'qpc': base + 3500,
          'data': {'revision': s},
        },
        {
          'sequence': null,
          'stage': 'content_painted',
          'qpc': base + 5000,
          'data': {'revision': s + 1},
        },
        {
          'sequence': s,
          'stage': 'state_observed',
          'qpc': base + 6000,
          'data': {'value': s == 4 ? 'wrong value' : 'Tick 000001'},
        },
      ]);
    }
    writeJson(path('native-input-trace.json'), events);
    File(path('present.csv')).writeAsStringSync(
      [
        'Application,ProcessID,SwapChainAddress,CPUStartQPC,DisplayLatency,DisplayedTime,MsBetweenPresents,MsBetweenDisplayChange',
        for (var s = 1; s <= 4; s++) ...[
          'fixture.exe,42,0x1,${1000000 * s + 4500},4.5,1.0,16.6,16.6',
          'other.exe,7,0x2,${1000000 * s + 5200},1.0,1.0,16.6,16.6',
          'fixture.exe,42,0x1,${1000000 * s + 20000},4.5,1.0,16.6,16.6',
        ],
      ].join('\n'),
    );
    final result = analyzeInput(temp.path),
        observations = array(result['observations']);
    expect(observations[0]['input_to_response_present_ms'], 2);
    expect(observations[0]['input_to_response_display_ms'], 6.5);
    expect(observations[0]['response_present_qpc'], 1020000);
    expect(observations[1]['input_to_response_present_ms'], isNull);
    expect(observations[2]['input_to_response_present_ms'], isNull);
    expect(at(result, 'response_presentation.frames_correlated'), 2);
    expect(
      at(result, 'response_presentation.input_to_response_present_ms.median'),
      2,
    );
    expect(result['complete_chains'], 1);
    expect(
      observations[1]['first_gap'],
      'GPUI mouse events to native click handler',
    );
    expect(
      observations[2]['first_gap'],
      'application handler to native application of update',
    );
    expect(
      observations[3]['first_gap'],
      'applied update to expected state readback',
    );
    File(path('present.csv')).writeAsStringSync(
      File(path('present.csv'))
          .readAsStringSync()
          .replaceAll('DisplayLatency', 'MsUntilDisplayed'),
    );
    expect(
      at(
        analyzeInput(temp.path),
        'response_presentation.input_to_response_display_ms.median',
      ),
      6.5,
    );
  });
  test('Dart traces correlate revisions and distinguish handler, apply and ack gaps', () {
    final inputs = [
      for (var s = 1; s <= 4; s++) {'sequence': s, 'packets_accepted': 2},
    ];
    writeJson(path('run.json'), {
      'implementation': 'dart',
      'workload': 'cell',
      'run_id': 'synthetic',
      'inputs': inputs,
    });
    writeJson(path('native-input-trace.json'), [
      for (var s = 1; s <= 4; s++) ...[
        for (final stage in [
          'gpui_mouse_down',
          'gpui_mouse_up',
          'native_click_handler',
        ])
          {'sequence': s, 'stage': stage, 'data': {}},
        if (s <= 2)
          {
            'sequence': null,
            'stage': 'update_applied',
            'data': {'revision': s + 1},
          },
      ],
    ]);
    writeJson(path('application.json.input-trace.json'), [
      for (var s = 1; s <= 3; s++) ...[
        {
          'sequence': s,
          'stage': 'application_handler',
          'data': {'update_ordinal': s, 'target_revision': s + 1},
        },
        if (s == 1) ...[
          {'sequence': s, 'stage': 'applied_acknowledged', 'data': {}},
          {
            'sequence': s,
            'stage': 'state_observed',
            'data': {
              'value': 'Tick 000001',
              'native': {'value': 'Tick 000001'},
            },
          },
        ],
      ],
    ]);
    final result = analyzeInput(temp.path),
        observations = array(result['observations']);
    expect(result['complete_chains'], 1);
    expect(
      observations[1]['first_gap'],
      'native application of update to Dart acknowledgement',
    );
    expect(
      observations[2]['first_gap'],
      'application handler to native application of update',
    );
    expect(
      observations[3]['first_gap'],
      'native click handler to application handler',
    );
    inputs[0]['packets_accepted'] = 1;
    writeJson(path('run.json'), {'implementation': 'dart', 'inputs': inputs});
    expect(
      analyzeInput(temp.path)['observations'][0]['first_gap'],
      'injection acceptance unverified',
    );
  });
  test('correctness checks counts, native readback, wheel displacement and view stage', () {
    final app = <String, dynamic>{
      'updates': 1,
      'cells_written': 1,
      'first_price': 'Tick 000001',
      'native_first_price': {'value': 'Tick 000001'},
      'native': {
        'tables': {
          'table': {
            'visible_rows': {'start': 0},
            'scroll_y': 0,
          },
        },
      },
    };
    expect(
      correctness(
        app,
        implementation: 'dart',
        workload: 'cell',
        rows: 100000,
        inputCount: 1,
      )['passed'],
      true,
    );
    expect(
      correctness(
        app,
        implementation: 'dart',
        workload: 'cell',
        rows: 100000,
        inputCount: 2,
      )['passed'],
      false,
    );
    expect(
      correctness(
        app,
        implementation: 'dart',
        workload: 'scroll',
        rows: 100000,
        inputCount: 1,
      )['passed'],
      false,
    );
    final view = {
      'updates': 5,
      'cells_written': 0,
      'first_price': '100.00',
      'scroll_y': 0,
      'view': {'stage': 1},
    };
    expect(
      correctness(
        view,
        implementation: 'rust',
        workload: 'view',
        rows: 100,
        inputCount: 5,
      )['passed'],
      true,
    );
    expect(
      correctness(
        view,
        implementation: 'rust',
        workload: 'view',
        rows: 100,
        inputCount: 6,
      )['passed'],
      false,
    );
  });
  test('series keep retries and report completed failures without pooling histograms', () {
    writeJson(path('pair-0/rust-cell/failure.json'), {
      'implementation': 'rust',
      'workload': 'cell',
      'run_id': 'pair-0',
      'error': 'focus lost',
    });
    writeJson(path('pair-0-retry2/rust-cell/run.json'), {
      ...run(impl: 'rust', workload: 'cell'),
      'run_id': 'pair-0-retry2',
      'seconds_requested': 2,
      'input_count': 10,
      'duration_ms': 2000,
      'correctness': {'passed': false},
    });
    Directory(path('pair-0-unrelated')).createSync();
    expect(seriesDirectories(temp.path, 'pair', 0).length, 2);
    final summary = summarize(temp.path, 'pair', 1, ['rust']);
    final group = (summary['groups'] as List).singleWhere(
      (g) => g['workload'] == 'cell',
    );
    expect(group['attempts'], 2);
    expect(group['completed'], 1);
    expect(group['correctness_failures'], 1);
    expect(group['equal_work_timing_eligible'], 0);
    expect(
      renderReport(summary, 'pair', 'Comparison'),
      contains('| cell | Rust + GPUI Kit | 2 | 1 | 1 | 0 | 0 |'),
    );
  });
  test(
    'invalid runner flags fail before building or injecting input',
    () async {
      for (final args in [
        ['--background-smoke', '--capture-present'],
        ['--trace-input', '--packaged'],
        ['--trace-input', '--implementation', 'flutter'],
        ['--release-records', '--implementation', 'rust'],
        ['--flutter-isolate', '--implementation', 'dart'],
        ['--rows', '100', '--workload', 'cell'],
        ['--seconds', '1'],
        ['--run-id', '../escape'],
        ['--unknown', 'x'],
      ]) {
        await expectLater(
          runBenchmark(args),
          throwsArgumentError,
          reason: '$args',
        );
      }
    },
  );
}
