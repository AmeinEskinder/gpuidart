import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('nodes omit the style key when no style is set', () {
    expect(const UiText('t', 'hi').toJson(), {
      'kind': 'text',
      'id': 't',
      'text': 'hi',
    });
    expect(UiColumn('root', const []).toJson(), {
      'kind': 'column',
      'id': 'root',
      'children': <Object>[],
    });
  });

  test('style serializes to the wire shape', () {
    const style = UiStyle(
      padding: [16, 8, 16, 8],
      gap: 12,
      width: UiSize.px(320),
      height: UiSize.full,
      align: UiAlign.center,
      justify: UiJustify.spaceBetween,
      background: UiColor.token(ThemeToken.muted),
      foreground: UiColor.token(ThemeToken.primaryForeground),
      borderColor: UiColor.token(ThemeToken.border),
      borderRadius: 8,
      fontSize: 14,
      fontWeight: UiFontWeight.semibold,
    );
    final encoded = jsonDecode(jsonEncode(style.toJson()));
    expect(encoded, {
      'padding': [16, 8, 16, 8],
      'gap': 12,
      'width': {'px': 320},
      'height': 'full',
      'align': 'center',
      'justify': 'space_between',
      'background': 'token:muted',
      'foreground': 'token:primary_foreground',
      'border_color': 'token:border',
      'border_radius': 8,
      'font_size': 14,
      'font_weight': 'semibold',
    });
    expect(UiSize.fit.toJson(), 'fit');
    final layout = jsonDecode(
      jsonEncode(
        const UiStyle(
          flex: 2,
          minWidth: UiSize.px(80),
          maxWidth: UiSize.full,
          minHeight: UiSize.fit,
          maxHeight: UiSize.px(600),
          inset: UiInset(top: 8, left: 12),
        ).toJson(),
      ),
    );
    expect(layout, {
      'flex': 2,
      'min_width': {'px': 80},
      'max_width': 'full',
      'min_height': 'fit',
      'max_height': {'px': 600},
      'inset': {'top': 8, 'left': 12},
    });
  });

  test('stack and scroll are containers with their own wire shape', () {
    final stack = UiStack('layers', [
      const UiText('under', 'Under'),
      const UiText('badge', 'Badge', style: UiStyle(inset: UiInset(top: 4))),
    ], semantics: const UiSemantics(role: UiRole.group, label: 'Layers'));
    expect(stack.children.length, 2);
    expect(stack.toJson()['kind'], 'stack');
    expect((stack.toJson()['children'] as List).length, 2);
    expect(stack.props().containsKey('children'), isFalse);
    final scroll = UiScroll('list', const [UiText('a', 'A')]);
    expect(scroll.toJson(), {
      'kind': 'scroll',
      'id': 'list',
      'children': [
        {'kind': 'text', 'id': 'a', 'text': 'A'},
      ],
    });
    expect(
      UiScroll('h', const [], axis: UiScrollAxis.horizontal).props()['axis'],
      'horizontal',
    );
    expect(
      () => UiScroll(
        's',
        const [],
        semantics: const UiSemantics(role: UiRole.button),
      ).props(),
      throwsArgumentError,
    );
  });

  test('style rides along on every node kind', () {
    const style = UiStyle(gap: 4);
    final nodes = <UiNode>[
      UiColumn('c', const [], style: style),
      UiRow('r', const [], style: style),
      const UiText('t', 'x', style: style),
      const UiButton('b', 'x', style: style),
      const UiInput('i', style: style),
      const UiTable('tbl', dataset: 'd', style: style),
    ];
    for (final node in nodes) {
      expect(node.toJson()['style'], {'gap': 4});
    }
  });

  test('hex colors validate format eagerly', () {
    expect(UiColor.hex('#1D4ED8').toJson(), '#1D4ED8');
    expect(UiColor.hex('#33415580').toJson(), '#33415580');
    for (final bad in ['#12345', '#1234567', 'GGGGGG', '1D4ED8', '', '#']) {
      expect(() => UiColor.hex(bad), throwsArgumentError, reason: bad);
    }
  });

  test('token enum covers exactly the documented wire names', () {
    expect(ThemeToken.values.map((token) => token.wire).toList(), [
      'background',
      'foreground',
      'primary',
      'primary_foreground',
      'secondary',
      'secondary_foreground',
      'muted',
      'muted_foreground',
      'accent',
      'accent_foreground',
      'danger',
      'danger_foreground',
      'border',
      'success',
      'warning',
      'info',
    ]);
  });

  test('padding must list four edges', () {
    expect(() => const UiStyle(padding: [8, 8]).toJson(), throwsArgumentError);
  });
  test('cached is a flag on the style and absent when false', () {
    expect(const UiStyle(height: UiSize.px(200), cached: true).toJson(), {
      'height': {'px': 200.0},
      'cached': true,
    });
    expect(
      const UiStyle(height: UiSize.px(200)).toJson().containsKey('cached'),
      isFalse,
    );
  });
}
