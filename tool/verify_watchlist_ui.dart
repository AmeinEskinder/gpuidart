import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main() async {
  final session = await DevSession.start(entry: 'example/watchlist/main.dart');
  final applicationPid = (await session.service.getVM()).pid;
  if (applicationPid == null) {
    throw StateError('VM service did not report an application PID');
  }
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<Map<String, dynamic>> step(String name) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-File',
      'tool/windows/watchlist_probe.ps1',
      '-AppProcessId',
      '$applicationPid',
      '-Step',
      name,
    ]);
    if (result.exitCode != 0) throw StateError('${result.stderr}');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return session.call('inspect');
  }

  try {
    await Directory('reports/sdk/visual').create(recursive: true);
    final cleared = await step('type-clear');
    require(
      cleared['query'] == '' &&
          cleared['state']['inputs']['search']['text'] == '' &&
          cleared['state']['tables']['watchlist']['row_count'] == 1000,
      'Typing then clearing left a stale search filter',
    );
    final searched = await step('search');
    require(
      searched['query'] == 'ALP0000',
      'Native typing did not reach the application',
    );
    require(
      searched['state']['tables']['watchlist']['row_count'] == 1,
      'Search did not filter the native table',
    );
    final selected = await step('select');
    require(
      selected['selected'] == 'ALP0000',
      'Native row selection did not reach Dart',
    );
    final saved = await step('pin');
    require(
      saved['state']['labels']['summary'] == '1 instrument shown · 1 saved',
      'Shortlist button did not update the record',
    );
    final updated = await step('tick');
    require(
      updated['ticks'] == 1 &&
          updated['state']['labels']['selection'].contains('100.07'),
      'Price button did not update the selected record',
    );
    await step('capture');
    final filtered = await step('shortlist');
    require(
      filtered['state']['tables']['watchlist']['row_count'] == 1,
      'Shortlist filter lost the saved row',
    );
    await File('reports/sdk/interaction.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'passed': true, 'input': 'Posted Windows mouse and character messages to the application HWND', 'limit': 'Functional UI check, not physical-input latency or IME composition', 'searched': searched, 'selected': selected, 'saved': saved, 'updated': updated, 'filtered': filtered})}\n',
    );
    stdout.writeln(
      'PASS: native typing, row selection, shortlist and price buttons updated the live application.',
    );
  } finally {
    await session.close();
  }
}
