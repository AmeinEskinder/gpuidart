import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';
import 'src/windows_powershell.dart';

Future<void> main() async {
  final session = await DevSession.start(entry: 'example/watchlist/main.dart');
  final applicationPid = (await session.service.getVM()).pid!;
  final report = <String, Object>{
    'passed': false,
    'application_pid': applicationPid,
  };
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<Map<String, dynamic>> step(String name) async {
    final result = await runWindowsPowerShell([
      '-NoProfile',
      '-File',
      'tool/windows/watchlist_probe.ps1',
      '-AppProcessId',
      '$applicationPid',
      '-Step',
      name,
    ]);
    if (result.exitCode != 0) throw StateError('$name: ${result.stderr}');
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return session.call('inspect');
  }

  try {
    await Directory('reports/sdk/visual').create(recursive: true);
    final selected = await step('select');
    final next = await step('down');
    require(
      next['selected'] != null && next['selected'] != selected['selected'],
      'Down did not change table selection',
    );
    final scrolled = await step('scroll');
    require(
      scrolled['state']['tables']['watchlist']['visible_rows']['start'] > 0,
      'Wheel did not move visible table rows',
    );
    report['keyboard_and_table_scroll'] = true;

    final focused = await step('focus-input');
    require(
      focused['state']['inputs']['search']['focused'] == true,
      'Search input did not acquire focus',
    );
    final unicode = await step('unicode');
    report['unicode_received'] = {
      'query': unicode['query'],
      'input': unicode['state']['inputs']['search'],
      'window': unicode['state']['window'],
    };
    require(
      unicode['query'] == '日本語😀' &&
          unicode['state']['inputs']['search']['text'] == '日本語😀',
      'Unicode text did not reach native input and Dart intact',
    );
    final backspace = await step('backspace');
    require(
      backspace['query'] == '日本語',
      'Backspace did not remove one complete emoji',
    );
    final cleared = await step('clear-unicode');
    require(
      cleared['query'] == '' &&
          cleared['state']['tables']['watchlist']['row_count'] == 1000,
      'Clearing Unicode did not restore the table',
    );
    report['unicode'] = {
      'text': unicode['query'],
      'after_backspace': backspace['query'],
      'cleared_rows': 1000,
    };

    final small = await step('small');
    require(
      small['state']['window']['width'] == 400 &&
          small['state']['window']['height'] == 360,
      'Window resize did not apply',
    );
    await step('capture-small');
    final footer = await step('screen-scroll');
    require(
      footer['state']['window']['scroll_y'] < 0,
      'Small screen did not scroll to its footer',
    );
    await step('capture-footer');
    report['small_window'] = {
      'viewport': small['state']['window'],
      'scrolled': footer['state']['window'],
    };
    final normal = await step('normal');
    report['restored_window'] = normal['state']['window'];
    require(
      normal['state']['window']['scroll_y'] == 0,
      'Restoring window size left the screen scrolled',
    );
    await step('select');
    final updates = <Object>[];
    for (var batch = 1; batch <= 5; batch++) {
      final state = await step('burst');
      require(
        state['ticks'] == batch * 100,
        'A delivered price update was lost in burst $batch: ${state['ticks']}',
      );
      require(
        state['state']['tables']['watchlist']['row_count'] == 1000,
        'Updates changed table size',
      );
      updates.add({
        'ticks': state['ticks'],
        'revision': state['dataset_revision'],
        'selection': state['state']['labels']['selection'],
        'metrics': state['metrics'],
      });
    }
    report['update_batches'] = updates;
    report['passed'] = true;
    report['limit'] = 'Posted Windows messages and functional checks; no IME or presentation-latency claim.';
    stdout.writeln(
      'PASS: keyboard navigation, table scrolling, Unicode editing, small-window scrolling and 500/500 price updates.',
    );
  } catch (error) {
    report['error'] = '$error';
    rethrow;
  } finally {
    await File(
      'reports/sdk/stability.json',
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
    await session.close();
  }
}
