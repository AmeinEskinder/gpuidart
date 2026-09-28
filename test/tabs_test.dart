import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test(
    'tabs preserve option identities and emit the established selected field',
    () {
      final options = [
        const UiChoiceOption('watchlist', 'Watchlist'),
        const UiChoiceOption('detail', 'Instrument'),
        const UiChoiceOption('blocked', 'Unavailable', disabled: true),
      ];
      final tabs = UiTabs(
        'pages',
        options: options,
        selected: 'watchlist',
        semantics: const UiSemantics(role: UiRole.tabList, label: 'Pages'),
      );
      options.clear();
      expect(tabs.toJson()['options'], hasLength(3));
      expect((tabs.toJson()['semantics'] as Map)['role'], 'tab_list');
      final event = decodeNativeEvent(
        utf8.encode(
          jsonEncode({
            'type': 'tab_change',
            'id': 'pages',
            'revision': 2,
            'selected': 'detail',
          }),
        ),
      );
      expect(event['selected'], 'detail');
      expect(
        () => decodeNativeEvent(
          utf8.encode(
            '{"type":"tab_change","id":"pages","revision":2,"selected":null}',
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test('tabs reject invalid choices, selections and false semantics', () {
    for (final options in <List<UiChoiceOption>>[
      [],
      [const UiChoiceOption('', 'A')],
      [const UiChoiceOption('a', '')],
      [const UiChoiceOption('a', 'A'), const UiChoiceOption('a', 'B')],
      [const UiChoiceOption('a', 'A', disabled: true)],
      [UiChoiceOption('a', 'x' * 1025)],
      [UiChoiceOption('x' * 257, 'A')],
      List.generate(33, (i) => UiChoiceOption('$i', 'X')),
    ]) {
      expect(
        () => UiTabs('tabs', options: options, selected: 'a').toJson(),
        throwsArgumentError,
      );
    }
    expect(
      () => UiTabs(
        'tabs',
        options: [const UiChoiceOption('a', 'A')],
        selected: 'missing',
      ).toJson(),
      throwsArgumentError,
    );
    expect(
      () => UiTabs(
        'tabs',
        options: [const UiChoiceOption('a', 'A')],
        selected: 'a',
        semantics: const UiSemantics(role: UiRole.button),
      ).toJson(),
      throwsArgumentError,
    );
  });
}
