import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:gpuidart/development.dart';

import 'app.dart';

Future<void> main(List<String> args) async {
  final rows = int.parse(
    args.where((a) => a.startsWith('--rows=')).firstOrNull?.substring(7) ??
        '1000',
  );
  final app = await TerminalApplication.open(rows: rows);
  registerGpuiReload(app.host, describe: app.describe);
  if (!const bool.fromEnvironment('dart.vm.product')) {
    registerExtension('ext.gpuidart.inspect', (_, _) async {
      await app.idle;
      return ServiceExtensionResponse.result(
        jsonEncode({
          'app': app.describe(),
          'state': await app.host.diagnose('inspect'),
          'metrics': app.host.metrics.read(),
        }),
      );
    });
    registerExtension('ext.gpuidart.repaint', (_, _) async {
      await app.idle;
      return ServiceExtensionResponse.result(
        jsonEncode(await app.host.diagnose('repaint', {'frames': 2})),
      );
    });
    registerExtension('ext.gpuidart.key', (_, parameters) async {
      await app.idle;
      await app.host.diagnose('repaint', {'frames': 1});
      final result = await app.host.diagnose('key', {
        'key': parameters['key'] ?? '',
      });
      await app.host.diagnose('repaint', {'frames': 1});
      return ServiceExtensionResponse.result(jsonEncode(result));
    });
    registerExtension('ext.gpuidart.prepare', (_, _) async {
      await app.host.diagnose('select_row', {'table': 'watchlist', 'row': 25});
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (app.market.selectedSymbol != 'BRK0025' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await app.idle;
      }
      if (app.market.selectedSymbol != 'BRK0025') {
        throw StateError('Selection did not settle');
      }
      await app.navigate('settings');
      await app.host.diagnose('focus', {'input': 'display-name'});
      for (final key in [
        Platform.isMacOS ? 'cmd-a' : 'ctrl-a',
        'backspace',
        'a',
        'd',
        'a',
        'tab',
        'right',
        'tab',
        'space',
      ]) {
        await app.host.diagnose('repaint', {'frames': 1});
        await app.host.diagnose('key', {'key': key});
        await app.host.diagnose('repaint', {'frames': 1});
        await app.idle;
      }
      await app.host.diagnose('focus', {'input': 'display-name'});
      for (final key in ['left', 'shift-left']) {
        await app.host.diagnose('key', {'key': key});
      }
      await app.idle;
      return ServiceExtensionResponse.result(jsonEncode(app.describe()));
    });
  }
  try {
    await app.host.done;
    if (app.failure != null) {
      stderr.writeln(app.failure);
      exitCode = 1;
    }
  } finally {
    await app.close();
  }
}
