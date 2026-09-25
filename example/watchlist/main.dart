import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:gpuidart/development.dart';
import 'package:gpuidart/gpuidart.dart';

import 'app.dart';

Future<void> main(List<String> args) async {
  final app = WatchlistApplication();
  final host = await GpuiHost.openView(
    app.build,
    datasets: [app.dataset],
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
          await app.select(host, selection.row);
        }
      });
    } else if (event.type == 'click') {
      switch (event.id) {
        case 'tick':
          enqueue(() => app.tick(host));
        case 'shortlist-toggle':
          enqueue(() => app.toggleShortlist(host));
        case 'shortlist-filter':
          enqueue(() => app.filter(host, shortlistOnly: !app.shortlistOnly));
      }
    }
  });

  if (!const bool.fromEnvironment('dart.vm.product')) {
    registerExtension('ext.gpuidart.inspect', (_, _) async {
      await pending;
      return ServiceExtensionResponse.result(
        jsonEncode({
          'state': await host.diagnose('inspect'),
          'query': app.query,
          'selected': app.selectedSymbol,
          'ticks': app.ticks,
          'dataset_revision': app.dataset.revision,
          'metrics': host.metrics.read(),
        }),
      );
    });
    registerExtension('ext.gpuidart.prepare', (_, _) async {
      await app.filter(host, query: 'ALP');
      await app.select(host, 25);
      await app.tick(host);
      final state = await host.diagnose('prepare', {
        'input': 'search',
        'text': 'ALP',
        'start': 0,
        'end': 3,
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

      await app.filter(host, query: 'ALP0000');
      require(app.dataset.rowCount == 1, 'Search did not filter the dataset');
      await app.select(host, 0);
      final messages = host.metrics.read()['data_messages'] as int;
      await app.tick(host);
      require(app.dataset.cell(0, 2) == '100.07', 'Price edit failed');
      require(
        (host.metrics.read()['data_messages'] as int) == messages + 1,
        'Price edit did not use one dataset transaction',
      );
      await app.toggleShortlist(host);
      await app.filter(host, query: '', shortlistOnly: true);
      require(
        app.dataset.rowCount == 1 && app.dataset.cell(0, 3) == 'Saved',
        'Shortlist filter failed',
      );
      await app.select(host, 0);
      await app.toggleShortlist(host);
      require(app.dataset.rowCount == 0, 'Removing a saved instrument failed');
      await app.filter(host, query: '', shortlistOnly: false);
      require(app.dataset.rowCount == 1000, 'Full list did not return');
      final cell = await host.diagnose('cell', {
        'dataset': 'instruments',
        'row': 0,
        'column': 2,
      });
      require(
        cell['value'] == '100.07',
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
  }
}
