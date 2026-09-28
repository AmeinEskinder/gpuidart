@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native tab keyboard activation returns a Dart selection request',
    () async {
      var selected = 'watchlist';
      final host = await GpuiHost.openView(
        () => UiColumn('root', [
          const UiInput('before', placeholder: 'Before'),
          UiTabs(
            'pages',
            options: const [
              UiChoiceOption('watchlist', 'Watchlist'),
              UiChoiceOption('disabled', 'Unavailable', disabled: true),
              UiChoiceOption('detail', 'Instrument'),
            ],
            selected: selected,
          ),
        ]),
      );
      try {
        await host.diagnose('repaint', {'frames': 2});
        await host.diagnose('focus', {'input': 'before'});
        await host.diagnose('key', {'key': 'tab'});
        await host.diagnose('key', {'key': 'right'});
        final next = host.events
            .firstWhere((e) => e.type == 'tab_change')
            .timeout(const Duration(seconds: 5));
        await host.diagnose('key', {'key': 'enter'});
        final event = await next;
        expect(event.id, 'pages');
        expect(event.selected, 'detail');
        expect(
          (await host.diagnose('inspect'))['controls']['pages']['selected'],
          'watchlist',
        );
        selected = event.selected!;
        await host.rebuild();
        final after = (await host.diagnose('inspect'))['controls']['pages'];
        expect(after['selected'], 'detail');
        expect(after['focused_option'], 'detail');
      } finally {
        await host.close();
      }
    },
  );
}
