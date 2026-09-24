import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:gpuidart/gpuidart.dart';

import 'app.dart';
import 'measure_data.dart';

Future<void> main(List<String> args) async {
  final rowArgument = args.where((arg) => arg.startsWith('--rows='));
  final app = DemoApplication(
    rowCount: rowArgument.isEmpty
        ? 10000
        : int.parse(rowArgument.single.substring(7)),
  );
  final host = await GpuiHost.openView(app.build, datasets: [app.quotes]);
  Future<void> handle(GpuiEvent event) async {
    if (event.type == 'click' && event.id == 'increment') {
      app.count++;
      await host.rebuild();
    } else if (event.type == 'input' && event.id == 'name') {
      app.name = event.value!;
      await host.rebuild();
    } else if (event.type == 'error') {
      stderr.writeln(event);
    }
  }

  final subscription = host.events.listen((event) {
    unawaited(
      handle(event).catchError((Object error) => stderr.writeln(error)),
    );
  });
  if (!const bool.fromEnvironment('dart.vm.product')) {
    registerExtension('ext.gpuidart.reassemble', (_, _) async {
      await host.rebuild();
      return ServiceExtensionResponse.result(
        jsonEncode({'heading': app.heading, 'count': app.count}),
      );
    });
    registerExtension('ext.gpuidart.inspect', (_, _) async {
      return ServiceExtensionResponse.result(
        jsonEncode({
          'state': await host.diagnose('inspect'),
          'dart': host.metrics.read(),
          'count': app.count,
          'name': app.name,
          'dataset': {
            'revision': app.quotes.revision,
            'value': app.quotes.cell(2000, 2),
            'native': await host.diagnose('cell', {
              'dataset': app.quotes.id,
              'row': 2000,
              'column': 2,
            }),
          },
        }),
      );
    });
    registerExtension('ext.gpuidart.prepare', (_, _) async {
      app.count = 7;
      app.name = 'Reload preserves this text';
      await host.editDataset(app.quotes, [const CellEdit(2000, 2, '987.65')]);
      await host.rebuild();
      final state = await host.diagnose('prepare', {
        'input': 'name',
        'text': 'Reload preserves this text',
        'start': 7,
        'end': 16,
        'table': 'quotes',
        'row': 2000,
      });
      return ServiceExtensionResponse.result(jsonEncode(state));
    });
    registerExtension('ext.gpuidart.close', (_, _) async {
      unawaited(host.close());
      return ServiceExtensionResponse.result('{}');
    });
  }

  try {
    if (args.contains('--measure-data')) {
      stdout.writeln(jsonEncode(await measureData(host, app)));
      await host.close();
    } else if (args.contains('--self-test') || args.contains('--measure')) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final before = await host.diagnose('inspect');
      final dartBefore = host.metrics.read();
      final after = await host.diagnose('repaint', {'frames': 30});
      final dartAfter = host.metrics.read();
      for (final field in [
        'description_builds',
        'ui_callbacks',
        'encoded_snapshots',
      ]) {
        if (dartBefore[field] != dartAfter[field]) {
          throw StateError('Unchanged repaint executed Dart UI work: $field');
        }
      }
      if ((dartAfter['ffi_callbacks'] as int) -
              (dartBefore['ffi_callbacks'] as int) !=
          1) {
        throw StateError('Expected only the diagnostic completion callback');
      }
      if ((after['native']['materializations'] as int) -
              (before['native']['materializations'] as int) <
          30) {
        throw StateError(
          'Repaint probe did not complete 30 native view builds',
        );
      }
      final updates = args.contains('--measure') ? 120 : 3;
      for (var i = 0; i < updates; i++) {
        app.count++;
        await host.editDataset(app.quotes, [
          CellEdit(0, 2, '${100 + i / 100}'),
        ]);
        await host.rebuild();
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final state = await host.diagnose('inspect');
      if (state['labels']['count'] != 'Count: $updates') {
        throw StateError('Snapshot updates did not reach the native view');
      }
      stdout.writeln(
        jsonEncode({
          'mode': const bool.fromEnvironment('gpuidart.packaged')
              ? 'aot'
              : 'jit',
          'rows': app.quotes.rowCount,
          'updates': updates,
          'unchanged_repaints': {
            'requested_frames': 30,
            'dart_before': dartBefore,
            'dart_after': dartAfter,
            'native_before': before,
            'native_after': after,
          },
          'dart': host.metrics.read(),
          'native': state,
          'process': {
            'rss_bytes': ProcessInfo.currentRss,
            'peak_rss_bytes': ProcessInfo.maxRss,
          },
        }),
      );
      await host.close();
    }
    await host.done;
  } finally {
    await host.close();
    await subscription.cancel();
  }
}
