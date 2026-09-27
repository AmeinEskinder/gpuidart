import 'dart:convert';
import 'dart:io';

import 'src/dev_session.dart';

Future<void> main(List<String> args) async {
  final output = File(args.single);
  if (output.existsSync())
    throw StateError('Refusing to replace ${output.path}');
  output.parent.createSync(recursive: true);
  final fixture = await Directory('.cache').createTemp('terminal-reload-');
  await Directory('${fixture.path}/terminal').create();
  await Directory('${fixture.path}/watchlist').create();
  final component = await File('example/terminal/app.dart')
      .copy('${fixture.path}/terminal/app.dart');
  final entry = await File('example/terminal/main.dart')
      .copy('${fixture.path}/terminal/main.dart');
  await File('example/watchlist/app.dart')
      .copy('${fixture.path}/watchlist/app.dart');
  final report = <String, Object?>{
    'passed': false,
    'platform': Platform.operatingSystem,
    'rows': 100000,
  };
  DevSession? session;
  void require(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    session = await DevSession.start(
      entry: entry.absolute.path,
      arguments: ['--rows=100000'],
    );
    report['prepared'] = await session.call('prepare');
    final before = await session.call('inspect');
    report['before'] = before;
    require(
      before['app']['theme'] == 'dark' &&
          before['app']['custom_accent'] == true &&
          before['app']['display_name'] == 'ada' &&
          before['app']['selected'] == 'BRK0025' &&
          before['app']['page'] == 'settings',
      'Preparation did not produce the declared state',
    );
    final source = await component.readAsString();
    require(source.contains("'Market terminal'"), 'Reload marker missing');
    await component.writeAsString(
      source.replaceFirst("'Market terminal'", "'Market terminal reloaded'"),
    );
    await session.reload();
    await session.call('repaint');
    final after = await session.call('inspect');
    report['after'] = after;
    require(
      after['state']['labels']['terminal-title'] == 'Market terminal reloaded',
      'Changed Dart code did not execute',
    );
    for (final key in ['theme', 'inputs', 'native_process_id']) {
      require(
        jsonEncode(before['state'][key]) == jsonEncode(after['state'][key]),
        'Native $key changed during reload',
      );
    }
    for (final key in [
      'page',
      'period',
      'theme',
      'custom_accent',
      'display_name',
      'selected',
      'instruments_revision',
      'history_revision',
    ]) {
      require(
        before['app'][key] == after['app'][key],
        'Application $key changed during reload',
      );
    }
    require(
      before['metrics']['data_bytes'] == after['metrics']['data_bytes'],
      'Reload republished data',
    );
    final mod = Platform.isMacOS ? 'cmd' : 'ctrl';
    await session.call('key', parameters: {'key': '$mod+2'});
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    Map<String, dynamic>? chart;
    do {
      chart = await session.call('inspect');
      if (chart['app']['page'] == 'instrument') break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    } while (DateTime.now().isBefore(deadline));
    report['instrument_after_reload'] = chart;
    require(
      chart['state']['charts']['price-chart']['points'].length == 20,
      'History did not survive reload',
    );
    report['passed'] = true;
  } catch (error, stack) {
    report['error'] = '$error';
    report['stack'] = '$stack';
    rethrow;
  } finally {
    await session?.close();
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
  }
}
