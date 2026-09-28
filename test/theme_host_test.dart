@TestOn('windows || linux || mac-os')
@Tags(['live-window'])
library;

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test(
    'theme builder follows rebuilds without replacing native controls',
    () async {
      var theme = const UiTheme.light();
      UiNode build() => UiColumn('root', [
        const UiInput('draft', placeholder: 'Draft'),
        const UiButton('save', 'Save'),
      ]);
      final host = await GpuiHost.openView(build, theme: () => theme);
      try {
        final before = await host.diagnose('inspect');
        theme = const UiTheme.dark(overrides: {ThemeToken.primary: '#2d6ac8'});
        await host.rebuild();
        final dark = await host.diagnose('inspect');
        expect(dark['theme']['descriptor']['mode'], 'dark');
        expect(dark['theme']['resolved']['primary'], '#2D6AC8');
        expect(dark['inputs'], before['inputs']);
        expect(host.metrics.descriptionBuilds, 2);
        expect(
          () => host.publish(
            build(),
            theme: const UiTheme(overrides: {ThemeToken.primary: 'url(bad)'}),
          ),
          throwsArgumentError,
        );
        await host.publish(build());
        final reset = await host.diagnose('inspect');
        expect(reset['theme'], before['theme']);
        expect(reset['inputs'], before['inputs']);
      } finally {
        await host.close();
      }
    },
  );
}
