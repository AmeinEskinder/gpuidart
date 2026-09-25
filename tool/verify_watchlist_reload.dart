import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main(List<String> args) async {
  var reportPath = 'reports/sdk/reload.json';
  var prepareDelayMs = 300;
  var tracing = false;
  for (final arg in args) {
    if (arg.startsWith('--report=')) {
      reportPath = arg.substring(9);
    } else if (arg.startsWith('--prepare-delay-ms=')) {
      prepareDelayMs = int.parse(arg.substring(19));
      if (prepareDelayMs < 0 || prepareDelayMs > 5000) {
        throw ArgumentError('Preparation delay must be 0..5000 ms');
      }
    } else if (arg == '--trace') {
      tracing = true;
    } else {
      throw ArgumentError('Unknown reload check option: $arg');
    }
  }
  final reportFile = File(reportPath).absolute;
  await reportFile.parent.create(recursive: true);
  final tracePath = '${reportFile.path}.trace.json';
  final fixture = await Directory('.cache').createTemp('watchlist-reload-');
  final app = await File('example/watchlist/app.dart')
      .copy('${fixture.path}/app.dart');
  final entry = await File('example/watchlist/main.dart')
      .copy('${fixture.path}/main.dart');
  final session = await DevSession.start(
    entry: entry.absolute.path,
    arguments: [if (tracing) '--trace=$tracePath'],
  );
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  final report = <String, Object?>{
    'passed': false,
    'prepare_delay_ms': prepareDelayMs,
    'tracing': tracing,
  };

  try {
    final applicationPid = (await session.service.getVM()).pid;
    require(applicationPid != null, 'Application PID was not reported');
    report['prepared'] = await session.call('prepare');
    final prepared = report['prepared'] as Map<String, dynamic>;
    require(
      prepared['tables']['watchlist']['visible_rows']['start'] == 25 &&
          prepared['tables']['watchlist']['scroll_y'] < 0,
      'Preparation acknowledged before the requested scroll was rendered',
    );
    await Future<void>.delayed(Duration(milliseconds: prepareDelayMs));
    final before = await session.call('inspect');
    report['before'] = before;
    final nativePid = before['state']['native_process_id'];
    require(
      nativePid is int && nativePid > 0,
      'Native process ID was not reported',
    );
    require(
      before['query'] == 'ALP' && before['ticks'] == 1,
      'Watchlist application state was not prepared',
    );
    require(
      before['selected'] == 'ALP0200',
      'Stable instrument selection was not prepared',
    );
    require(
      before['state']['inputs']['search']['focused'] == true,
      'Search did not retain focus',
    );
    require(
      before['state']['tables']['watchlist']['scroll_y'] < 0,
      'Watchlist did not scroll',
    );
    final source = await app.readAsString();
    await app.writeAsString(
      source.replaceFirst("'Market watch'", "'Market watch reloaded'"),
    );
    await session.reload();
    final after = await session.call('inspect');
    report['after'] = after;
    require(
      after['state']['native_process_id'] == nativePid,
      'Native process changed during reload',
    );
    require(
      (await session.service.getVM()).pid == applicationPid,
      'Application process changed during reload',
    );
    require(
      after['state']['labels']['title'] == 'Market watch reloaded',
      'Changed component code did not run',
    );
    for (final field in ['query', 'selected', 'ticks', 'dataset_revision']) {
      require(
        before[field] == after[field],
        'Application state changed during reload: $field',
      );
    }
    for (final field in ['inputs', 'tables']) {
      require(
        jsonEncode(before['state'][field]) == jsonEncode(after['state'][field]),
        'Native state changed during reload: $field',
      );
    }
    require(
      before['metrics']['data_bytes'] == after['metrics']['data_bytes'],
      'Reload republished table records',
    );
    report['after_repaint'] = await session.call('repaint');
    final afterRepaint = report['after_repaint'] as Map<String, dynamic>;
    for (final field in ['inputs', 'tables']) {
      require(
        jsonEncode(before['state'][field]) == jsonEncode(afterRepaint[field]),
        'Native state changed after rendering reloaded code: $field',
      );
    }
    await app.writeAsString('$source\nthis is invalid Dart;\n');
    var rejected = false;
    try {
      await session.reload();
    } on StateError {
      rejected = true;
    }
    require(rejected, 'Invalid source was accepted');
    final intact = await session.call('inspect');
    require(
      intact['state']['labels']['title'] == 'Market watch reloaded',
      'Rejected reload changed the running app',
    );
    for (var i = 1; i <= 10; i++) {
      final heading = 'Market watch recovered $i';
      await app.writeAsString(
        source.replaceFirst("'Market watch'", "'$heading'"),
      );
      await session.reload();
      final recovered = await session.call('inspect');
      report['latest_recovery'] = recovered;
      require(
        recovered['state']['native_process_id'] == nativePid,
        'Recovery restarted the native process',
      );
      require(
        recovered['state']['labels']['title'] == heading,
        'Reload did not recover after invalid source',
      );
      require(
        (await session.service.getVM()).pid == applicationPid,
        'Recovery restarted the application',
      );
      for (final field in ['query', 'selected', 'ticks', 'dataset_revision']) {
        require(
          before[field] == recovered[field],
          'Repeated reload changed $field',
        );
      }
      for (final field in ['inputs', 'tables']) {
        require(
          jsonEncode(before['state'][field]) ==
              jsonEncode(recovered['state'][field]),
          'Repeated reload changed native $field',
        );
      }
      require(
        before['metrics']['data_bytes'] == recovered['metrics']['data_bytes'],
        'Repeated reload republished data',
      );
      final rendered = await session.call('repaint');
      report['latest_recovery_repaint'] = rendered;
      for (final field in ['inputs', 'tables']) {
        require(
          jsonEncode(before['state'][field]) == jsonEncode(rendered[field]),
          'Repeated reload changed native $field after rendering',
        );
      }
    }
    report.addAll({
      'passed': true,
      'same_application_process_id': applicationPid,
      'same_native_process_id': nativePid,
      'launcher_process_id': session.process.pid,
      'same_isolate_id': session.isolateId,
      'changed_code_executed': true,
      'invalid_source_rejected': rejected,
      'successful_reloads': 11,
      'recovered_after_invalid_source': true,
    });
    stdout.writeln(
      'PASS: watchlist code reload preserved application state, input text/focus/selection, table identity and scroll without republishing data.',
    );
  } catch (error) {
    report['error'] = '$error';
    try {
      report['after_failure_repaint'] = await session.call('repaint');
      report['after_failure_inspect'] = await session.call('inspect');
    } catch (inspectionError) {
      report['failure_inspection_error'] = '$inspectionError';
    }
    rethrow;
  } finally {
    try {
      await reportFile.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    } finally {
      await session.close();
    }
  }
}
