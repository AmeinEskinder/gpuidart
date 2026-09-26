import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/menus.dart' show encodeMenus;
import 'package:test/test.dart';

void main() {
  test('menus encode stable actions and separators with immutable entries', () {
    final entries = <UiMenuEntry>[
      const UiMenuAction(
        'settings',
        'Settings',
        action: 'app.settings',
        checked: true,
      ),
      const UiMenuSeparator(),
    ];
    final menu = UiMenu('app', 'Terminal', entries);
    entries.clear();
    final wire = encodeMenus([menu]);
    expect(wire.single['items'], hasLength(2));
    expect((wire.single['items'] as List).first['action'], 'app.settings');
    expect((wire.single['items'] as List).first['checked'], true);
  });
  test(
    'menus reject duplicate identities, unbounded and malformed entries',
    () {
      const item = UiMenuAction('a', 'A', action: 'app.a');
      for (final menus in [
        List.generate(9, (i) => UiMenu('$i', 'Menu', [item])),
        [
          UiMenu('a', 'A', [item]),
          UiMenu('a', 'B', [item]),
        ],
        [UiMenu('a', 'A', [])],
        [
          UiMenu('a', 'A', [item, item]),
        ],
        [UiMenu('a', 'A', List.filled(65, const UiMenuSeparator()))],
        [
          UiMenu('a', 'A', [UiMenuAction('a', 'x' * 1025, action: 'a')]),
        ],
        [
          UiMenu('a', 'A', [const UiMenuAction('a', 'A', action: '')]),
        ],
      ]) {
        expect(() => encodeMenus(menus), throwsArgumentError);
      }
    },
  );
}
