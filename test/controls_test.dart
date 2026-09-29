import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  test('date pickers encode, validate and decode their changes', () {
    expect(
      const UiDatePicker(
        'due',
        value: '2026-09-29',
        placeholder: 'Due',
      ).toJson(),
      {
        'kind': 'date_picker',
        'id': 'due',
        'value': '2026-09-29',
        'placeholder': 'Due',
        'disabled': false,
      },
    );
    expect(const UiDatePicker('due').toJson().containsKey('value'), isFalse);
    for (final invalid in ['2026-02-30', '2026-9-9', 'tomorrow', '20260929']) {
      expect(UiDatePicker('due', value: invalid).toJson, throwsArgumentError);
    }
    expect(
      const UiDatePicker(
        'due',
        semantics: UiSemantics(role: UiRole.textbox),
      ).toJson,
      throwsArgumentError,
    );
    Map<String, dynamic> decode(Map<String, Object?> event) =>
        decodeNativeEvent(utf8.encode(jsonEncode(event)));
    final changed = decode({
      'type': 'date_change',
      'revision': 3,
      'id': 'due',
      'date': '2026-10-01',
    });
    expect(changed['date'], '2026-10-01');
    expect(
      decode({
        'type': 'date_change',
        'revision': 3,
        'id': 'due',
        'date': null,
      })['date'],
      isNull,
    );
    expect(
      () => decode({'type': 'date_change', 'revision': 3, 'id': 'due'}),
      throwsFormatException,
    );
    expect(
      () => decode({
        'type': 'date_change',
        'revision': 3,
        'id': 'due',
        'date': '2026-13-01',
      }),
      throwsFormatException,
    );
  });

  test('icons and images encode and validate', () {
    expect(
      const UiIcon(
        'i',
        'search',
        size: 20,
        color: UiColor.token(ThemeToken.primary),
      ).toJson(),
      {
        'kind': 'icon',
        'id': 'i',
        'name': 'search',
        'size': 20.0,
        'color': 'token:primary',
      },
    );
    expect(const UiIcon('i', 'Search').toJson, throwsArgumentError);
    expect(const UiIcon('i', 'search', size: 4).toJson, throwsArgumentError);
    expect(
      const UiImage.path('p', r'C:\pictures\logo.PNG', width: 64).toJson(),
      {
        'kind': 'image',
        'id': 'p',
        'path': r'C:\pictures\logo.PNG',
        'width': 64.0,
        'fit': 'contain',
      },
    );
    expect(const UiImage.path('p', 'notes.txt').toJson, throwsArgumentError);
    final inline = UiImage.bytes(
      'b',
      [1, 2, 3],
      format: UiImageFormat.png,
      fit: UiImageFit.scaleDown,
    ).toJson();
    expect(inline['bytes'], base64Encode([1, 2, 3]));
    expect(inline['format'], 'png');
    expect(inline['fit'], 'scale_down');
    expect(inline.containsKey('path'), isFalse);
    expect(
      UiImage.bytes('b', const [], format: UiImageFormat.png).toJson,
      throwsArgumentError,
    );
    expect(
      const UiImage.path('p', 'a.png', height: 0).toJson,
      throwsArgumentError,
    );
    expect(
      const UiImage.path(
        'p',
        'a.png',
        semantics: UiSemantics(role: UiRole.image, label: 'Logo'),
      ).toJson()['semantics'],
      {'role': 'image', 'label': 'Logo'},
    );
    expect(
      const UiIcon(
        'i',
        'search',
        semantics: UiSemantics(role: UiRole.button),
      ).toJson,
      throwsArgumentError,
    );
  });

  test('switch, progress and separator encode and validate', () {
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

  test('canvases and animations encode and validate', () {
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

  test('menu buttons take application menu entries', () {
    final menu = UiMenuButton(
      'file',
      'File',
      items: const [
        UiMenuAction('open', 'Open', action: 'file.open'),
        UiMenuSeparator(),
        UiMenuAction('wrap', 'Word wrap', action: 'view.wrap', checked: true),
      ],
    );
    expect(menu.toJson(), {
      'kind': 'menu_button',
      'id': 'file',
      'label': 'File',
      'items': [
        {
          'kind': 'action',
          'id': 'open',
          'label': 'Open',
          'action': 'file.open',
          'checked': false,
          'disabled': false,
        },
        {'kind': 'separator'},
        {
          'kind': 'action',
          'id': 'wrap',
          'label': 'Word wrap',
          'action': 'view.wrap',
          'checked': true,
          'disabled': false,
        },
      ],
    });
    expect(
      UiMenuButton('m', 'File', items: const []).toJson,
      throwsArgumentError,
    );
    expect(
      UiMenuButton(
        'm',
        '',
        items: const [UiMenuAction('a', 'A', action: 'x')],
      ).toJson,
      throwsArgumentError,
    );
  });

  test('trees encode their items and decode selection and expansion', () {
    final tree = UiTree(
      'files',
      items: const [
        UiTreeItem(
          'src',
          'src',
          expanded: true,
          children: [UiTreeItem('main', 'main.dart', disabled: true)],
        ),
        UiTreeItem('license', 'LICENSE'),
      ],
      selected: 'main',
    );
    expect(tree.toJson(), {
      'kind': 'tree',
      'id': 'files',
      'items': [
        {
          'id': 'src',
          'label': 'src',
          'expanded': true,
          'children': [
            {'id': 'main', 'label': 'main.dart', 'disabled': true},
          ],
        },
        {'id': 'license', 'label': 'LICENSE'},
      ],
      'selected': 'main',
    });
    expect(
      UiTree('t', items: const [UiTreeItem('a', 'A')], selected: 'b').toJson,
      throwsArgumentError,
      reason: 'selection names an item',
    );
    expect(
      UiTree(
        't',
        items: const [UiTreeItem('a', 'A'), UiTreeItem('a', 'B')],
      ).toJson,
      throwsArgumentError,
      reason: 'unique IDs',
    );
    expect(const UiTreeItem('', 'A').toJson, throwsArgumentError);
    expect(const UiTreeItem('a', '').toJson, throwsArgumentError);
    Map<String, dynamic> decode(Map<String, Object?> event) =>
        decodeNativeEvent(utf8.encode(jsonEncode(event)));
    expect(
      decode({
        'type': 'tree_select',
        'revision': 1,
        'id': 'files',
        'item': 'main',
      })['item'],
      'main',
    );
    expect(
      decode({
        'type': 'tree_expand',
        'revision': 1,
        'id': 'files',
        'item': 'src',
        'expanded': false,
      })['expanded'],
      false,
    );
    expect(
      () => decode({
        'type': 'tree_expand',
        'revision': 1,
        'id': 'files',
        'item': 'src',
      }),
      throwsFormatException,
    );
    expect(
      () => decode({'type': 'tree_select', 'revision': 1, 'id': 'files'}),
      throwsFormatException,
    );
  });

  test('panes encode their specs and decode resize events', () {
    final panes = UiPanes(
      'split',
      [const UiText('left', 'L'), const UiText('right', 'R')],
      panes: const [UiPane(size: 200, minSize: 100, maxSize: 400), UiPane()],
    );
    expect(panes.toJson(), {
      'kind': 'panes',
      'id': 'split',
      'panes': [
        {'size': 200.0, 'min': 100.0, 'max': 400.0},
        <String, Object>{},
      ],
      'children': [
        {'kind': 'text', 'id': 'left', 'text': 'L'},
        {'kind': 'text', 'id': 'right', 'text': 'R'},
      ],
    });
    expect(
      UiPanes('v', const [
        UiText('a', 'A'),
      ], axis: UiPanesAxis.vertical).toJson()['axis'],
      'vertical',
    );
    expect(
      UiPanes(
        'bad',
        [const UiText('a', 'A')],
        panes: const [UiPane(), UiPane()],
      ).toJson,
      throwsArgumentError,
      reason: 'one spec per child or none',
    );
    for (final pane in const [
      UiPane(size: 0),
      UiPane(size: -1),
      UiPane(size: 9000),
      UiPane(minSize: 300, maxSize: 200),
      UiPane(size: 50, minSize: 100),
      UiPane(size: double.nan),
    ]) {
      expect(pane.toJson, throwsArgumentError, reason: '$pane');
    }
    Map<String, dynamic> decode(Map<String, Object?> event) =>
        decodeNativeEvent(utf8.encode(jsonEncode(event)));
    final resized = decode({
      'type': 'panes_resize',
      'revision': 2,
      'id': 'split',
      'sizes': [300, 300.5],
    });
    expect(resized['sizes'], [300, 300.5]);
    for (final invalid in <Map<String, Object?>>[
      {'type': 'panes_resize', 'revision': 2, 'id': 'split'},
      {
        'type': 'panes_resize',
        'revision': 2,
        'id': 'split',
        'sizes': ['wide'],
      },
      {
        'type': 'panes_resize',
        'revision': 2,
        'id': 'split',
        'sizes': [-1],
      },
    ]) {
      expect(() => decode(invalid), throwsFormatException);
    }
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
  test('lists encode their binding and list selections decode', () {
    const list = UiList(
      'names',
      dataset: 'people',
      column: 1,
      view: UiTableView(sort: [UiSort(1)]),
      selected: 'p2',
    );
    expect(jsonDecode(jsonEncode(list.toJson())), {
      'kind': 'list',
      'id': 'names',
      'dataset': 'people',
      'column': 1,
      'view': {
        'sort': [
          {'column': 1, 'direction': 'asc'},
        ],
      },
      'selected': 'p2',
    });
    expect(
      const UiList(
        'l',
        dataset: 'd',
        column: 0,
      ).toJson().containsKey('selected'),
      isFalse,
    );
    expect(
      const UiList('l', dataset: '', column: 0).toJson,
      throwsArgumentError,
    );
    expect(
      const UiList('l', dataset: 'd', column: 64).toJson,
      throwsArgumentError,
    );
    expect(
      const UiList('l', dataset: 'd', column: 0, selected: '').toJson,
      throwsArgumentError,
    );
    expect(
      const UiList(
        'l',
        dataset: 'd',
        column: 0,
        view: UiTableView(group: UiGroup(0)),
      ).toJson,
      throwsArgumentError,
    );
    expect(
      const UiList(
        'l',
        dataset: 'd',
        column: 0,
        semantics: UiSemantics(role: UiRole.table),
      ).toJson,
      throwsArgumentError,
    );
    final event = decodeNativeEvent(
      utf8.encode(
        jsonEncode({
          'type': 'list_select',
          'revision': 3,
          'id': 'names',
          'dataset': 'people',
          'dataset_revision': 2,
          'row': 1,
          'record': 'p3',
        }),
      ),
    );
    expect(event['record'], 'p3');
    expect(
      () => decodeNativeEvent(
        utf8.encode(
          jsonEncode({
            'type': 'list_select',
            'revision': 3,
            'id': 'names',
            'dataset': 'people',
            'dataset_revision': 2,
            'row': 1,
          }),
        ),
      ),
      throwsFormatException,
    );
  });
}
