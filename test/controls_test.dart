import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test('select freezes options and encodes separate identities and labels', () {
    final options = [const UiSelectOption('dark', 'Dark')];
    final select = UiSelect(
      's',
      options: options,
      selected: 'dark',
      placeholder: 'Choose',
      style: const UiStyle(foreground: UiColor.token(ThemeToken.primary)),
    );
    options.clear();
    expect(select.toJson(), {
      'kind': 'select',
      'id': 's',
      'options': [
        {'id': 'dark', 'label': 'Dark'},
      ],
      'selected': 'dark',
      'placeholder': 'Choose',
      'disabled': false,
      'style': {'foreground': 'token:primary'},
    });
    expect(() => select.options.clear(), throwsUnsupportedError);
    expect(
      UiSelect('s', options: select.options).toJson().containsKey('selected'),
      false,
    );
    for (final options in <List<UiSelectOption>>[
      [],
      [const UiSelectOption('', 'X')],
      [const UiSelectOption('x', '')],
      [const UiSelectOption('x', 'X'), const UiSelectOption('x', 'Y')],
      [UiSelectOption('x' * 257, 'X')],
      [UiSelectOption('x', 'é' * 513)],
      List.generate(257, (i) => UiSelectOption('$i', 'X')),
    ]) {
      expect(
        () => UiSelect('s', options: options).toJson(),
        throwsArgumentError,
      );
    }
    expect(
      () =>
          UiSelect('s', options: select.options, selected: 'missing').toJson(),
      throwsArgumentError,
    );
    expect(
      () => UiSelect(
        's',
        options: select.options,
        placeholder: 'é' * 513,
      ).toJson(),
      throwsArgumentError,
    );
  });

  test('select events require a nullable selected ID', () {
    final event = <String, Object?>{
      'type': 'select_change',
      'id': 's',
      'revision': 1,
      'selected': 'dark',
    };
    Map<String, dynamic> decode(Map<String, Object?> value) =>
        decodeNativeEvent(utf8.encode(jsonEncode(value)));
    expect(decode(event)['selected'], 'dark');
    expect(decode({...event, 'selected': null})['selected'], isNull);
    expect(() => decode({...event, 'selected': 1}), throwsFormatException);
    event.remove('selected');
    expect(() => decode(event), throwsFormatException);
  });
  test('slider validates native bounds and serializes theme styles', () {
    const slider = UiSlider(
      's',
      min: 0,
      max: 100,
      step: 5,
      number: 20,
      style: UiStyle(foreground: UiColor.token(ThemeToken.primary)),
    );
    expect(slider.toJson(), {
      'kind': 'slider',
      'id': 's',
      'min': 0.0,
      'max': 100.0,
      'step': 5.0,
      'number': 20.0,
      'disabled': false,
      'style': {'foreground': 'token:primary'},
    });
    for (final (min, max, step, number) in <(double, double, double, double)>[
      (0, 0, 1, 0),
      (5, 1, 1, 3),
      (0, 10, 0, 5),
      (0, 10, -1, 5),
      (0, 10, 11, 5),
      (0, 10, 1, 11),
      (0, 10, 1, -1),
      (-1000001, 10, 1, 5),
      (0, 1000001, 1, 5),
      (999990, 1000000, 0.00001, 999995),
      (0, 10, double.infinity, 5),
      (0, 10, 1, double.nan),
    ]) {
      expect(
        () => UiSlider(
          's',
          min: min,
          max: max,
          step: step,
          number: number,
        ).toJson(),
        throwsArgumentError,
      );
    }
  });

  test('slider events reject malformed and unbounded values', () {
    Map<String, dynamic> decode(Object? number) => decodeNativeEvent(
      utf8.encode(
        jsonEncode({
          'type': 'slider_change',
          'revision': 1,
          'id': 's',
          'number': number,
        }),
      ),
    );
    expect(decode(2.5)['number'], 2.5);
    expect(decode(0)['number'], 0);
    for (final number in [null, '2', true, 1000001, -1000001]) {
      expect(() => decode(number), throwsFormatException);
    }
  });
  test('checkbox wire preserves value, disabled state and theme styling', () {
    const node = UiCheckbox(
      'notifications',
      'Notifications',
      checked: true,
      disabled: true,
      style: UiStyle(foreground: UiColor.token(ThemeToken.primary)),
    );
    expect(jsonDecode(jsonEncode(node.toJson())), {
      'kind': 'checkbox',
      'id': 'notifications',
      'label': 'Notifications',
      'checked': true,
      'disabled': true,
      'style': {'foreground': 'token:primary'},
    });
    expect(
      const UiCheckbox('c', '', checked: false).toJson()['disabled'],
      false,
    );
    UiCheckbox('c', 'é' * 512, checked: false).toJson();
    expect(
      () => UiCheckbox('c', 'é' * 513, checked: false).toJson(),
      throwsArgumentError,
    );
  });

  test('checkbox requests require a boolean and source identity', () {
    final event = {
      'type': 'checkbox_change',
      'id': 'notifications',
      'revision': 2,
      'checked': true,
    };
    Map<String, dynamic> decode(Map<String, Object?> data) =>
        decodeNativeEvent(utf8.encode(jsonEncode(data)));
    expect(decode(event)['checked'], true);
    for (final invalid in [
      {...event, 'checked': 'true'},
      {...event, 'checked': 1},
      {...event, 'checked': null},
      {...event, 'revision': 0},
      {...event, 'id': null},
    ]) {
      expect(() => decode(invalid), throwsFormatException);
    }
  });
}
