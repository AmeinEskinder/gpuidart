import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:gpuidart/src/runtime_info.dart';

import 'package:gpuidart/development.dart';
import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/tracing.dart';

import 'app.dart';

Future<void> main(List<String> args) async {
  final tracePath = args
      .where((arg) => arg.startsWith('--trace='))
      .firstOrNull
      ?.substring(8);
  final trace = tracePath == null ? null : GpuiTrace(capacity: 8192);
  final rowCountArg = args
      .where((arg) => arg.startsWith('--rows='))
      .firstOrNull
      ?.substring(7);
  final rowCount = rowCountArg == null ? 1000 : int.parse(rowCountArg);
  if (rowCount < 26 || rowCount > 100000) {
    throw ArgumentError('--rows must be 26..100000');
  }
  final app = WatchlistApplication(count: rowCount);
  final host = await GpuiHost.openView(
    app.build,
    datasets: [app.dataset],
    actions: WatchlistApplication.actions,
    trace: trace,
    window: const GpuiWindowOptions(
      title: 'Market watch',
      width: 960,
      height: 720,
    ),
  );
  registerGpuiReload(
    host,
    describe: () => {
      'heading': app.heading,
      'selected': app.selectedSymbol,
      'query': app.query,
      'ticks': app.ticks,
    },
  );
  var pending = Future<void>.value();
  var closing = false;
  Timer? search;
  var searchRevision = 0;
  void enqueue(Future<void> Function() operation) {
    pending = pending.then((_) async {
      if (closing) return;
      try {
        await operation();
      } catch (error, stack) {
        if (!closing) stderr.writeln('$error\n$stack');
      }
    });
  }

  final subscription = host.events.listen((event) {
    if (event.type == 'closed') {
      closing = true;
      search?.cancel();
      return;
    }
    if (event.type == 'error') {
      stderr.writeln(event);
      return;
    }
    if (event.type == 'input' && event.id == 'search') {
      final query = event.value!;
      final revision = ++searchRevision;
      search?.cancel();
      search = Timer(
        const Duration(milliseconds: 180),
        () => enqueue(() async {
          if (revision == searchRevision && query != app.query) {
            await app.filter(host, query: query);
          }
        }),
      );
    } else if (event.tableSelection case final selection?) {
      enqueue(() async {
        if (selection.dataset == app.dataset.id &&
            selection.datasetRevision == app.dataset.revision) {
          // Selection is keyed by record ID; the view row is for debugging.
          await app.select(host, selection.record);
        }
      });
    } else if (event.action case final action?) {
      switch (action.name) {
        case 'app.search':
          enqueue(() => app.focusSearch(host));
        case 'watchlist.add':
          enqueue(() => app.addSelectedToShortlist(host));
      }
    } else if (event.type == 'click') {
      switch (event.id) {
        case 'tick':
          enqueue(() => app.tick(host));
        case 'shortlist-toggle':
          enqueue(() => app.toggleShortlist(host));
        case 'shortlist-filter':
          enqueue(() => app.filter(host, shortlistOnly: !app.shortlistOnly));
        case 'sort-price':
          enqueue(() => app.cycleSort(host));
      }
    }
  });

  if (!const bool.fromEnvironment('dart.vm.product')) {
    registerExtension('ext.gpuidart.repaint', (_, _) async {
      await pending;
      return ServiceExtensionResponse.result(
        jsonEncode(await host.diagnose('repaint', {'frames': 2})),
      );
    });
    registerExtension('ext.gpuidart.inspect', (_, _) async {
      await pending;
      return ServiceExtensionResponse.result(
        jsonEncode({
          'state': await host.diagnose('inspect'),
          'formatted': {
            // Row 0 of the current view: the formatting of what is on screen.
            'price': await host.diagnose('formatted_cell', {
              'table': 'watchlist',
              'row': 0,
              'column': 2,
            }),
            'change': await host.diagnose('formatted_cell', {
              'table': 'watchlist',
              'row': 0,
              'column': 3,
            }),
          },
          'query': app.query,
          'selected': app.selectedSymbol,
          'ticks': app.ticks,
          'dataset_revision': app.dataset.revision,
          'metrics': host.metrics.read(),
        }),
      );
    });
    registerExtension('ext.gpuidart.prepare', (_, _) async {
      // '0' matches every symbol (all are zero-padded), so the view keeps all
      // records and scrolling to the selected record is meaningful. The
      // select_row diagnostic performs the native selection a pointer would.
      await app.filter(host, query: '0');
      await host.diagnose('select_row', {'table': 'watchlist', 'row': 25});
      await app.select(host, 'BRK0025');
      await app.tick(host);
      final state = await host.diagnose('prepare', {
        'input': 'search',
        'text': '0',
        'start': 0,
        'end': 1,
        'table': 'watchlist',
        'row': 25,
      });
      return ServiceExtensionResponse.result(jsonEncode(state));
    });
  }

  try {
    if (args.contains('--self-test')) {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      void require(bool condition, String message) {
        if (!condition) throw StateError(message);
      }

      Future<Map<String, dynamic>> table() async {
        final state = await host.diagnose('inspect');
        return state['tables']['watchlist'] as Map<String, dynamic>;
      }

      // Search publishes a view; the dataset keeps all 1,000 records.
      await app.filter(host, query: 'ALP0000');
      var watchlist = await table();
      require(
        watchlist['view']['view_rows'] == 1 && watchlist['row_count'] == 1000,
        'Search did not drive the native view',
      );
      await app.select(host, 'ALP0000');
      final messages = host.metrics.read()['data_messages'] as int;
      await app.tick(host);
      require(app.dataset.cell(0, 2) == '100.0700', 'Price edit failed');
      require(
        (host.metrics.read()['data_messages'] as int) == messages + 1,
        'Price edit did not use one dataset transaction',
      );
      final price = await host.diagnose('formatted_cell', {
        'table': 'watchlist',
        'row': 0,
        'column': 2,
      });
      require(price['text'] == '100.07', 'Price format did not render');
      final change = await host.diagnose('formatted_cell', {
        'table': 'watchlist',
        'row': 0,
        'column': 3,
      });
      require(
        change['color'] == 'token:danger' && change['icon'] == 'arrow_down',
        'Change rules did not render',
      );
      // Note: self-test drives app methods directly, so native pointer
      // selection is covered by the live UI verifier instead.
      await app.toggleShortlist(host);
      await app.filter(host, query: '', shortlistOnly: true);
      watchlist = await table();
      require(
        watchlist['view']['view_rows'] == 1 &&
            app.dataset.cell(0, 4) == 'Saved',
        'Shortlist view lost the saved record',
      );
      await app.toggleShortlist(host);
      watchlist = await table();
      require(
        watchlist['view']['view_rows'] == 0,
        'Removing a saved instrument failed',
      );
      await app.filter(host, query: '', shortlistOnly: false);
      watchlist = await table();
      require(
        watchlist['view']['view_rows'] == 1000 && app.dataset.rowCount == 1000,
        'Full list did not return',
      );
      final cell = await host.diagnose('cell', {
        'dataset': 'instruments',
        'row': 0,
        'column': 2,
      });
      require(
        cell['value'] == '100.0700',
        'Native price was lost during filtering',
      );
      final state = await host.diagnose('inspect');
      stdout.writeln(
        jsonEncode({
          'application': 'watchlist',
          'mode': const bool.fromEnvironment('gpuidart.packaged')
              ? 'aot'
              : 'jit',
          'passed': true,
          'rows': app.dataset.rowCount,
          'native': state,
          if (Platform.isLinux || Platform.isMacOS)
            'runtime': {
              'application': readRuntimeInfo(),
              'ui': await host.diagnose('runtime'),
            },
          'metrics': host.metrics.read(),
        }),
      );
      await host.close();
    }
    await host.done;
  } finally {
    closing = true;
    search?.cancel();
    await host.close();
    await subscription.cancel();
    await pending;
    if (tracePath != null) await trace!.writeTo(tracePath);
  }
}
