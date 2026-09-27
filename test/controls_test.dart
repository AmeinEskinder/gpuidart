import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test('switch, radio group, progress and separator encode and validate', () {
    expect(const UiSwitch('wifi', 'Wi-Fi', checked: true).toJson(), {
      'kind': 'switch',
      'id': 'wifi',
      'label': 'Wi-Fi',
      'checked': true,
      'disabled': false,
    });
    expect(
      UiSwitch('s', 'é' * 513, checked: false).toJson,
      throwsArgumentError,
    );
    final group = UiRadioGroup(
      'mode',
      options: const [
        UiSelectOption('auto', 'Automatic'),
        UiSelectOption('manual', 'Manual'),
      ],
      selected: 'auto',
      horizontal: true,
    );
    expect(group.toJson(), {
      'kind': 'radio_group',
      'id': 'mode',
      'options': [
        {'id': 'auto', 'label': 'Automatic'},
        {'id': 'manual', 'label': 'Manual'},
      ],
      'selected': 'auto',
      'disabled': false,
      'horizontal': true,
    });
    expect(
      UiRadioGroup(
        'm',
        options: const [UiSelectOption('a', 'A')],
        selected: 'b',
      ).toJson,
      throwsArgumentError,
    );
    expect(
      UiRadioGroup(
        'm',
        options: const [UiSelectOption('a', 'A'), UiSelectOption('a', 'B')],
      ).toJson,
      throwsArgumentError,
    );
    expect(const UiProgress('p', value: 42.5).toJson()['value'], 42.5);
    expect(const UiProgress('p').toJson().containsKey('value'), isFalse);
    expect(const UiProgress('p', value: 101).toJson, throwsArgumentError);
    expect(const UiSeparator('r', label: 'Advanced').toJson(), {
      'kind': 'separator',
      'id': 'r',
      'vertical': false,
      'label': 'Advanced',
    });
    expect(
      const UiButton('b', 'Save', tooltip: 'Ctrl+S').toJson()['tooltip'],
      'Ctrl+S',
    );
    expect(
      UiButton('b', 'Save', tooltip: 'é' * 513).toJson,
      throwsArgumentError,
    );
    expect(
      const UiSwitch(
        's',
        'Wi-Fi',
        checked: true,
        semantics: UiSemantics(role: UiRole.toggle),
      ).toJson()['semantics'],
      {'role': 'switch'},
    );
    expect(
      const UiProgress('p', semantics: UiSemantics(role: UiRole.slider)).toJson,
      throwsArgumentError,
    );
  });

  test('tabs, canvases and animations encode and validate', () {
    final tabs = UiTabs(
      'pages',
      tabs: const [UiSelectOption('a', 'A'), UiSelectOption('b', 'B')],
      selected: 'b',
      variant: UiTabVariant.pill,
    );
    expect(tabs.toJson(), {
      'kind': 'tabs',
      'id': 'pages',
      'tabs': [
        {'id': 'a', 'label': 'A'},
        {'id': 'b', 'label': 'B'},
      ],
      'selected': 'b',
      'variant': 'pill',
    });
    expect(
      UiTabs(
        't',
        tabs: const [UiSelectOption('a', 'A')],
        selected: 'missing',
      ).toJson,
      throwsArgumentError,
    );
    final canvas = UiCanvas('chart', [
      const UiRect(
        0,
        0,
        50,
        20,
        fill: UiColor.token(ThemeToken.primary),
        radius: 4,
      ),
      UiPolyline(const [(0, 100), (50, 20)], stroke: UiColor.hex('#ff0000')),
      const UiLine(0, 0, 10, 10, UiColor.token(ThemeToken.border), width: 2),
      const UiCircle(5, 5, 3, fill: UiColor.token(ThemeToken.danger)),
    ], style: const UiStyle(width: UiSize.px(200), height: UiSize.px(100)));
    final encoded = jsonDecode(jsonEncode(canvas.toJson()));
    expect(encoded['kind'], 'canvas');
    expect(encoded['commands'], [
      {
        'op': 'rect',
        'x': 0,
        'y': 0,
        'width': 50,
        'height': 20,
        'fill': 'token:primary',
        'radius': 4,
      },
      {
        'op': 'polyline',
        'points': [
          [0, 100],
          [50, 20],
        ],
        'stroke': '#ff0000',
      },
      {
        'op': 'line',
        'x1': 0,
        'y1': 0,
        'x2': 10,
        'y2': 10,
        'color': 'token:border',
        'width': 2,
      },
      {'op': 'circle', 'cx': 5, 'cy': 5, 'radius': 3, 'fill': 'token:danger'},
    ]);
    expect(const UiRect(0, 0, -1, 1).toJson, throwsArgumentError);
    expect(const UiRect(9000, 0, 1, 1).toJson, throwsArgumentError);
    expect(UiPolyline(const [(0, 0)]).toJson, throwsArgumentError);
    expect(UiPolyline(const [(0, 0), (1, 1)]).toJson, throwsArgumentError);
    expect(
      UiCanvas('c', List.filled(4097, const UiRect(0, 0, 1, 1))).toJson,
      throwsArgumentError,
    );
    const animation = UiAnimation(
      duration: Duration(milliseconds: 300),
      easing: UiEasing.linear,
      repeat: true,
      key: 'in',
      opacity: (0, 1),
      offset: ((0, 0), (100, 0)),
    );
    expect(jsonDecode(jsonEncode(animation.toJson())), {
      'duration_ms': 300,
      'easing': 'linear',
      'repeat': true,
      'key': 'in',
      'opacity': [0, 1],
      'offset': [
        [0, 0],
        [100, 0],
      ],
    });
    expect(
      const UiStyle(
        animation: UiAnimation(
          duration: Duration(milliseconds: 200),
          opacity: (0, 1),
        ),
      ).toJson()['animation'],
      {
        'duration_ms': 200,
        'opacity': [0.0, 1.0],
      },
    );
    for (final invalid in [
      const UiAnimation(duration: Duration.zero, opacity: (0, 1)),
      const UiAnimation(duration: Duration(milliseconds: 100)),
      const UiAnimation(duration: Duration(milliseconds: 100), opacity: (0, 2)),
      const UiAnimation(
        duration: Duration(milliseconds: 100),
        offset: ((0, 0), (9000, 0)),
      ),
    ]) {
      expect(invalid.toJson, throwsArgumentError);
    }
  });

  test('menu buttons encode entries and menu selections decode', () {
    final menu = UiMenuButton(
      'file',
      'File',
      items: const [
        UiMenuItem('open', 'Open'),
        UiMenuDivider(),
        UiMenuItem('save', 'Save', disabled: true),
        UiMenuItem('wrap', 'Word wrap', checked: true),
      ],
    );
    expect(menu.toJson(), {
      'kind': 'menu_button',
      'id': 'file',
      'label': 'File',
      'items': [
        {'id': 'open', 'label': 'Open'},
        {'divider': true},
        {'id': 'save', 'label': 'Save', 'disabled': true},
        {'id': 'wrap', 'label': 'Word wrap', 'checked': true},
      ],
    });
    expect(
      UiMenuButton('m', 'File', items: const []).toJson,
      throwsArgumentError,
    );
    expect(
      UiMenuButton(
        'm',
        'File',
        items: const [UiMenuItem('a', 'A'), UiMenuItem('a', 'B')],
      ).toJson,
      throwsArgumentError,
    );
    expect(
      UiMenuButton('m', '', items: const [UiMenuItem('a', 'A')]).toJson,
      throwsArgumentError,
    );
    final event = decodeNativeEvent(
      utf8.encode(
        jsonEncode({
          'type': 'menu_select',
          'revision': 1,
          'id': 'file',
          'item': 'save',
        }),
      ),
    );
    expect(event['item'], 'save');
    expect(
      () => decodeNativeEvent(
        utf8.encode(
          jsonEncode({'type': 'menu_select', 'revision': 1, 'id': 'file'}),
        ),
      ),
      throwsFormatException,
    );
  });

  test('switch and radio events decode with their values', () {
    Map<String, dynamic> decode(Map<String, Object?> event) =>
        decodeNativeEvent(utf8.encode(jsonEncode(event)));
    expect(
      decode({
        'type': 'switch_change',
        'revision': 1,
        'id': 'wifi',
        'checked': true,
      })['checked'],
      true,
    );
    expect(
      () => decode({'type': 'switch_change', 'revision': 1, 'id': 'wifi'}),
      throwsFormatException,
    );
    expect(
      decode({
        'type': 'radio_change',
        'revision': 1,
        'id': 'mode',
        'selected': 'manual',
      })['selected'],
      'manual',
    );
    expect(
      () => decode({
        'type': 'radio_change',
        'revision': 1,
        'id': 'mode',
        'selected': null,
      }),
      throwsFormatException,
    );
  });

  test('confirmation dialog encodes labels, styles and bounded content', () {
    const dialog = UiConfirmDialog(
      'reset',
      'Reset',
      title: 'Reset preferences?',
      message: 'Discard draft',
      style: UiStyle(background: UiColor.token(ThemeToken.secondary)),
    );
    expect(dialog.toJson(), {
      'kind': 'confirm_dialog',
      'id': 'reset',
      'label': 'Reset',
      'title': 'Reset preferences?',
      'message': 'Discard draft',
      'confirm_label': 'Confirm',
      'cancel_label': 'Cancel',
      'disabled': false,
      'style': {'background': 'token:secondary'},
    });
    for (final invalid in [
      const UiConfirmDialog('r', '', title: 'Title', message: ''),
      const UiConfirmDialog('r', 'Reset', title: '', message: ''),
      const UiConfirmDialog(
        'r',
        'Reset',
        title: 'Title',
        message: '',
        confirmLabel: '',
      ),
      const UiConfirmDialog(
        'r',
        'Reset',
        title: 'Title',
        message: '',
        cancelLabel: '',
      ),
      UiConfirmDialog('r', 'é' * 513, title: 'Title', message: ''),
      UiConfirmDialog('r', 'Reset', title: 'Title', message: 'é' * 4097),
    ]) {
      expect(invalid.toJson, throwsArgumentError);
    }
    UiConfirmDialog('r', 'Reset', title: 'Title', message: 'é' * 4096).toJson();
  });

  test('dialog results require a boolean confirmation', () {
    Map<String, dynamic> decode(Object? confirmed) => decodeNativeEvent(
      utf8.encode(
        jsonEncode({
          'type': 'dialog_result',
          'revision': 1,
          'id': 'reset',
          'confirmed': confirmed,
        }),
      ),
    );
    expect(decode(true)['confirmed'], true);
    expect(decode(false)['confirmed'], false);
    for (final value in [null, 1, 'true']) {
      expect(() => decode(value), throwsFormatException);
    }
  });
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
