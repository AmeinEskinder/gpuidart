import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test('radio groups preserve option identities and emit the established selected field', () {
    final options = [
      const UiChoiceOption('watchlist', 'Watchlist'),
      const UiChoiceOption('detail', 'Instrument'),
      const UiChoiceOption('blocked', 'Unavailable', disabled: true),
    ];
    final group = UiRadioGroup(
      'pages',
      options: options,
      selected: 'watchlist',
      semantics: const UiSemantics(role: UiRole.radioGroup, label: 'Pages'),
    );
    options.clear();
    expect(group.toJson()['options'], hasLength(3));
    expect((group.toJson()['semantics'] as Map)['role'], 'radio_group');
    final event = decodeNativeEvent(
      utf8.encode(
        jsonEncode({
          'type': 'radio_change',
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
          '{"type":"radio_change","id":"pages","revision":2,"selected":null}',
        ),
      ),
      throwsFormatException,
    );
  });
  test(
    'radio groups reject invalid choices, selections and false semantics',
    () {
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
          () => UiRadioGroup(
            'radio groups',
            options: options,
            selected: 'a',
          ).toJson(),
          throwsArgumentError,
        );
      }
      expect(
        () => UiRadioGroup(
          'radio groups',
          options: [const UiChoiceOption('a', 'A')],
          selected: 'missing',
        ).toJson(),
        throwsArgumentError,
      );
      expect(
        () => UiRadioGroup(
          'radio groups',
          options: [const UiChoiceOption('a', 'A')],
          selected: 'a',
          semantics: const UiSemantics(role: UiRole.button),
        ).toJson(),
        throwsArgumentError,
      );
    },
  );
}
