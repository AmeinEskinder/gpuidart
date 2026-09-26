@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'live menu builder shares action shortcuts and honors disabled state',
    () async {
      var disabled = false;
      final host = await GpuiHost.openView(
        () => const UiInput('draft', placeholder: 'Draft'),
        actions: const [UiAction(name: 'app.settings', keys: 'ctrl+,')],
        menus: () => [
          UiMenu('app', 'Terminal', [
            UiMenuAction(
              'settings',
              'Settings',
              action: 'app.settings',
              disabled: disabled,
            ),
          ]),
        ],
      );
      try {
        await host.diagnose('repaint', {'frames': 2});
        await host.diagnose('focus', {'input': 'draft'});
        final next = host.events
            .firstWhere((e) => e.type == 'action')
            .timeout(const Duration(seconds: 5));
        await host.diagnose('key', {'key': 'ctrl-,'});
        final event = await next;
        expect(event.action!.name, 'app.settings');
        expect(event.action!.context, 'global');
        disabled = true;
        await host.rebuild();
        final callbacks = host.metrics.uiCallbacks;
        await host.diagnose('key', {'key': 'ctrl-,'});
        expect(host.metrics.uiCallbacks, callbacks);
        disabled = false;
        await host.rebuild();
        final enabled = host.events
            .firstWhere((e) => e.type == 'action')
            .timeout(const Duration(seconds: 5));
        await host.diagnose('key', {'key': 'ctrl-,'});
        expect((await enabled).revision, 3);
      } finally {
        await host.close();
      }
    },
  );
}
