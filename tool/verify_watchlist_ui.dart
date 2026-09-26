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
    await step('focus-input');
    final cleared = await step('type-clear');
    require(
      cleared['query'] == '' &&
          cleared['state']['inputs']['search']['text'] == '' &&
          cleared['state']['tables']['watchlist']['row_count'] == 1000 &&
          cleared['state']['tables']['watchlist']['view']['view_rows'] == 1000,
      'Typing then clearing left a stale search filter',
    );
    final searched = await step('search');
    require(
      searched['query'] == 'ALP0000',
      'Native typing did not reach the application',
    );
    // Search drives a native view; the dataset keeps all 1,000 records.
    require(
      searched['state']['tables']['watchlist']['row_count'] == 1000 &&
          searched['state']['tables']['watchlist']['view']['view_rows'] == 1 &&
          searched['state']['tables']['watchlist']['view']['source_rows'] ==
              1000,
      'Search did not filter the native table view',
    );
    // Declarative cell formatting renders the visible row.
    require(
      searched['formatted']['price']['text'] == '100.00',
      'Price number format did not render: ${searched['formatted']['price']}',
    );
    require(
      searched['formatted']['change']['text'] == '-0.20' &&
          searched['formatted']['change']['color'] == 'token:danger' &&
          searched['formatted']['change']['icon'] == 'arrow_down',
      'Change rules did not render: ${searched['formatted']['change']}',
    );
    final selected = await step('select');
    require(
      selected['selected'] == 'ALP0000',
      'Native row selection did not reach Dart',
    );
    require(
      selected['state']['tables']['watchlist']['selection']['record'] ==
          'ALP0000',
      'Selection did not carry the record ID',
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
    require(
      updated['formatted']['price']['text'] == '100.07',
      'Edited price did not render through the number format',
    );
    await step('capture');
    final filtered = await step('shortlist');
    require(
      filtered['state']['tables']['watchlist']['view']['view_rows'] == 1 &&
          filtered['state']['tables']['watchlist']['selection']['record'] ==
              'ALP0000',
      'Shortlist view lost the saved row or its selection',
    );
    // Widening the view keeps the selected record; sorting moves its row.
    await step('focus-input');
    await step('refine-search');
    final widened = await step('shortlist');
    require(
      widened['query'] == 'ALP' &&
          widened['state']['tables']['watchlist']['view']['view_rows'] == 125 &&
          widened['state']['tables']['watchlist']['selection']['record'] ==
              'ALP0000' &&
          widened['state']['tables']['watchlist']['selection']['row'] == 0,
      'Widening the view filter lost the record selection',
    );
    final sorted = await step('sort');
    final sortedSelection = sorted['state']['tables']['watchlist']['selection'];
    require(
      sortedSelection['record'] == 'ALP0000',
      'Sorting lost the selected record',
    );
    require(
      sortedSelection['row'] == 124,
      'Sorted view did not move the selected record: $sortedSelection',
    );
    // ctrl+enter on the table context adds the clicked record to the shortlist.
    await step('select-second');
    final added = await step('action-add');
    require(
      added['state']['labels']['summary'].contains('2 saved'),
      'The ctrl+enter action did not add the selected record: ${added['state']['labels']['summary']}',
    );
    // ctrl+f focuses the search input from the table.
    final focused = await step('action-search');
    require(
      focused['state']['inputs']['search']['focused'] == true,
      'The ctrl+f action did not focus the search input',
    );
    await File('reports/sdk/interaction.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'passed': true, 'input': 'Posted Windows mouse and character messages to the application HWND', 'limit': 'Functional UI check, not physical-input latency or IME composition', 'searched': searched, 'selected': selected, 'saved': saved, 'updated': updated, 'filtered': filtered, 'sorted': sorted, 'added': added, 'focused': focused})}\n',
    );
    stdout.writeln(
      'PASS: native typing, view filtering, record selection through sort, formatted cells, shortlist, price updates and scoped actions updated the live application.',
    );
  } finally {
    await session.close();
  }
}
