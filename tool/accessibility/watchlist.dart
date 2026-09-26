import 'dart:convert';
import 'dart:io';

import '../src/dev_session.dart';
import 'client.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: watchlist.dart REPORT.json');
  }
  final file = File(args.single);
  if (file.existsSync()) throw StateError('Refusing to replace ${file.path}');
  file.parent.createSync(recursive: true);
  final steps = <Map<String, Object?>>[];
  final report = <String, Object?>{
    'platform': Platform.operatingSystem,
    'records': 100000,
    'scope': 'External platform tree/actions against the actual Watchlist application; no screen reader or visual claim.',
    'steps': steps,
    'passed': false,
  };
  DevSession? session;
  try {
    session = await DevSession.start(
      entry: 'example/watchlist/main.dart',
      arguments: ['--rows=100000'],
    );
    final app = session;
    final initial = await app.call('inspect');
    final process = initial['state']['native_process_id'] as int;
    final initialMessages = initial['metrics']['data_messages'];
    final rowId = jsonEncode(['watchlist', 'instruments', 'record', 'BRK0025']);
    dynamic find(List nodes, String id) =>
        nodes.where((n) => n['id'] == id).singleOrNull;
    Future<Map<String, dynamic>> until(
      String name,
      bool Function(List, Map<String, dynamic>) ready,
    ) async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      Map<String, dynamic>? tree;
      Map<String, dynamic>? state;
      do {
        tree = await platformQuery(process);
        state = await app.call('inspect');
        if (ready(tree['nodes'] as List, state)) {
          steps.add({
            'step': name,
            'tree': tree,
            'query': state['query'],
            'selected': state['selected'],
            'data_messages': state['metrics']['data_messages'],
          });
          return tree;
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      } while (DateTime.now().isBefore(deadline));
      steps.add({'step': name, 'tree': tree, 'state': state, 'failed': true});
      throw StateError('Watchlist platform state did not settle: $name');
    }

    report['unavailable'] = [
      if (Platform.isWindows) 'UIA Grid/Table coordinate patterns remain unavailable; row SelectionItem is supplied by the pinned adapter patch.',
      if (Platform.isLinux) 'Pinned AT-SPI adapter has no EditableText; search uses GPUI diagnostic keys and external Text reads.',
    ];
    bool rowSelected(List nodes) =>
        hasPlatformRole(find(nodes, rowId), 'row') &&
        find(nodes, rowId)?['selected'] == true;
    Future<void> search(String text) async {
      if (Platform.isLinux) {
        await app.call('accessibility_text', parameters: {'text': text});
      } else {
        await platformQuery(
          process,
          operation: 'set-value',
          id: 'search',
          value: text,
        );
      }
    }

    final first = await until(
      '100k table with bounded visible semantics',
      (nodes, state) =>
          hasPlatformRole(find(nodes, 'watchlist'), 'table') &&
          find(nodes, 'watchlist')?['name'] == 'Instruments' &&
          nodes.any(
            (n) => hasPlatformRole(n, 'cell') && n['name'] == 'ALP0000',
          ),
    );
    if ((first['nodes'] as List).length >= 500) {
      throw StateError('100k semantics exceeded viewport bound');
    }
    await search('BRK0025');
    await until(
      'search filters native dataset',
      (nodes, state) =>
          state['query'] == 'BRK0025' &&
          find(nodes, 'search')?['value'] == 'BRK0025' &&
          find(nodes, rowId) != null &&
          state['state']['tables']['watchlist']['view']['view_rows'] == 1 &&
          state['state']['tables']['watchlist']['row_count'] == 100000,
    );
    await platformQuery(process, operation: 'select', id: rowId);
    await until(
      'platform row selection reaches application',
      (nodes, state) => state['selected'] == 'BRK0025' && rowSelected(nodes),
    );
    await platformQuery(process, operation: 'invoke', id: 'tick');
    await until(
      'formatted incremental price reaches platform cell',
      (nodes, state) =>
          state['ticks'] == 1 &&
          nodes.any((n) => hasPlatformRole(n, 'cell') && n['name'] == '101.82'),
    );
    await search('');
    await until(
      'cleared filter preserves record selection',
      (nodes, state) =>
          state['query'] == '' &&
          state['selected'] == 'BRK0025' &&
          rowSelected(nodes) &&
          state['state']['tables']['watchlist']['view']['view_rows'] == 100000,
    );
    await platformQuery(process, operation: 'invoke', id: 'sort-price');
    await until(
      'sorting preserves selected platform record identity',
      (nodes, state) =>
          state['selected'] == 'BRK0025' &&
          rowSelected(nodes) &&
          state['state']['tables']['watchlist']['selection']['row'] > 99000,
    );
    final after = await app.call('inspect');
    if (after['metrics']['data_messages'] != (initialMessages as int) + 1) {
      throw StateError('Views republished data: ${after['metrics']}');
    }
    await search('ALP0000');
    await until(
      'filtered-out selection disappears',
      (nodes, state) =>
          state['query'] == 'ALP0000' &&
          state['selected'] == null &&
          find(nodes, rowId) == null &&
          nodes.any(
            (n) => hasPlatformRole(n, 'cell') && n['name'] == 'ALP0000',
          ),
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    try {
      await session?.close();
    } catch (error) {
      report['close_error'] = '$error';
      report['passed'] = false;
      exitCode = 1;
    }
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(
      'Saved ${file.path}: passed=${report['passed']}, steps=${steps.length}',
    );
  }
}
