import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
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
