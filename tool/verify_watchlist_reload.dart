import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main() async {
  final fixture = await Directory('.cache').createTemp('watchlist-reload-');
  final app = await File('example/watchlist/app.dart')
      .copy('${fixture.path}/app.dart');
  final entry = await File('example/watchlist/main.dart')
      .copy('${fixture.path}/main.dart');
  final session = await DevSession.start(entry: entry.absolute.path);
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    final applicationPid = (await session.service.getVM()).pid;
    require(applicationPid != null, 'Application PID was not reported');
    await session.call('prepare');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final before = await session.call('inspect');
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
    }
    await Directory('reports/sdk').create(recursive: true);
    await File('reports/sdk/reload.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'same_application_process_id': applicationPid, 'launcher_process_id': session.process.pid, 'same_isolate_id': session.isolateId, 'changed_code_executed': true, 'invalid_source_rejected': rejected, 'successful_reloads': 11, 'recovered_after_invalid_source': true, 'before': before, 'after': after})}\n',
    );
    stdout.writeln(
      'PASS: watchlist code reload preserved application state, input text/focus/selection, table identity and scroll without republishing data.',
    );
  } finally {
    await session.close();
  }
}
