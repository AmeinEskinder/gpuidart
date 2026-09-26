import 'package:gpuidart/gpuidart.dart';
import 'package:test/test.dart';

void main() {
  test('every control carries names without changing visible content', () {
    const semantics = UiSemantics(label: 'Accessible name');
    final nodes = <UiNode>[
      UiColumn('column', [], semantics: semantics),
      UiRow('row', [], semantics: semantics),
      const UiText('text', 'Visible', semantics: semantics),
      const UiButton('button', 'Go', semantics: semantics),
      const UiCheckbox('check', 'Check', checked: true, semantics: semantics),
      const UiSlider(
        'slider',
        min: 0,
        max: 100,
        step: 1,
        number: 20,
        semantics: semantics,
      ),
      UiSelect(
        'select',
        options: [const UiSelectOption('a', 'A')],
        semantics: semantics,
      ),
      const UiInput('input', semantics: semantics),
      const UiTable('table', dataset: 'data', semantics: semantics),
      const UiConfirmDialog(
        'dialog',
        'Reset',
        title: 'Reset?',
        message: 'Sure?',
        semantics: semantics,
      ),
    ];
    for (final node in nodes) {
      expect(node.toJson()['semantics'], {'label': 'Accessible name'});
    }
    expect(nodes[2].toJson()['text'], 'Visible');
    expect(nodes[4].toJson()['checked'], true);
    expect(
      const UiText('plain', 'Plain').toJson().containsKey('semantics'),
      false,
    );
  });

  test('roles cannot advertise incompatible behavior', () {
    for (final (kind, role) in [
      ('column', UiRole.group),
      ('row', UiRole.list),
      ('text', UiRole.label),
      ('button', UiRole.button),
      ('checkbox', UiRole.checkbox),
      ('slider', UiRole.slider),
      ('input', UiRole.textbox),
      ('select', UiRole.combobox),
      ('table', UiRole.table),
      ('confirm_dialog', UiRole.button),
    ]) {
      expect(UiSemantics(role: role).toJson(kind), {'role': role.wire});
      expect(
        () => const UiSemantics(
          role: UiRole.heading,
          headingLevel: 2,
        ).toJson(kind),
        kind == 'text' ? returnsNormally : throwsArgumentError,
      );
    }
    expect(const UiSemantics(role: UiRole.listItem).toJson('row'), {
      'role': 'list_item',
    });
  });

  test('UTF-8 bounds and heading levels are validated', () {
    for (final annotation in [
      const UiSemantics(label: ''),
      UiSemantics(label: 'x' * 1025),
      UiSemantics(label: '\u65e5' * 342),
      const UiSemantics(role: UiRole.heading),
      const UiSemantics(role: UiRole.heading, headingLevel: 7),
      const UiSemantics(headingLevel: 1),
    ]) {
      expect(() => annotation.toJson('text'), throwsArgumentError);
    }
    expect(UiSemantics(label: 'x' * 1024).toJson('text'), isNotEmpty);
    expect(
      const UiSemantics(role: UiRole.heading, headingLevel: 2).toJson('text'),
      {'role': 'heading', 'heading_level': 2},
    );
  });
}
