import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  // The tested source copy can be edited without changing the developer's files.
  final fixture = await Directory('.cache').createTemp('reload-');
  final app = await File('example/app.dart').copy('${fixture.path}/app.dart');
  final entry = await File('example/main.dart')
      .copy('${fixture.path}/main.dart');
  await File('example/measure_data.dart')
      .copy('${fixture.path}/measure_data.dart');
  final session = await DevSession.start(entry: entry.absolute.path);
  try {
    await session.call('prepare');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final before = await session.call('inspect');
    final inputBefore = before['state']['inputs']['name'] as Map;
    require(before['count'] == 7, 'Application state was not prepared');
    require(
      before['dataset']['value'] == '987.65' &&
          before['dataset']['native']['value'] == '987.65' &&
          before['dataset']['revision'] == 2,
      'Edited dataset state was not prepared on both sides',
    );
    require(
      before['name'] == 'Reload preserves this text',
      'Dart text state was not prepared',
    );
    require(inputBefore['focused'] == true, 'Input was not focused');
    require(
      inputBefore['selection']['start'] == 7 &&
          inputBefore['selection']['end'] == 16,
      'Selection was not prepared',
    );
    require(
      before['state']['tables']['quotes']['visible_rows']['start'] > 1000,
      'Table did not scroll',
    );

    final source = await app.readAsString();
    const newHeading = 'Reloaded Dart component';
    await app.writeAsString(
      source.replaceFirst('Dart application · GPUI Kit controls', newHeading),
    );
    final timer = Stopwatch()..start();
    final reload = await session.reload();
    final reloadUs = timer.elapsedMicroseconds;
    final after = await session.call('inspect');
    require(
      reload['heading'] == newHeading,
      'Changed Dart code did not execute',
    );
    require(
      after['state']['labels']['title'] == newHeading,
      'Native description did not receive new code output',
    );
    for (final field in ['count', 'name', 'dataset']) {
      require(
        jsonEncode(before[field]) == jsonEncode(after[field]),
        'Dart state changed: $field',
      );
    }
    for (final field in ['inputs', 'tables']) {
      require(
        jsonEncode(before['state'][field]) == jsonEncode(after['state'][field]),
        'Native state changed: $field',
      );
    }
    for (final field in ['data_messages', 'data_bytes']) {
      require(
        before['dart'][field] == after['dart'][field],
        'Code reload republished dataset records',
      );
    }
    await app.writeAsString('$source\nthis is deliberately invalid Dart;\n');
    var rejected = false;
    try {
      await session.reload();
    } on StateError {
      rejected = true;
    }
    require(rejected, 'Invalid source was accepted');
    final afterRejected = await session.call('inspect');
    require(
      afterRejected['state']['labels']['title'] == newHeading,
      'Rejected reload replaced running code',
    );
    final report = {
      'source_changed': 'DemoApplication.heading',
      'same_process_id': session.process.pid,
      'same_isolate_id': session.isolateId,
      'reload_and_reassemble_us': reloadUs,
      'invalid_source_rejected': rejected,
      'before': before,
      'after': after,
    };
    await Directory('reports').create();
    await File(
      'reports/reload.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    stdout.writeln(
      'PASS: code reload preserved Dart state, input text/focus/selection, table identity and scroll. Invalid source left the live application intact.',
    );
  } finally {
    await session.close();
    // Deliberately retain this small fixture under .cache for failure diagnosis.
  }
}
