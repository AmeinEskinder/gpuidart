import 'dart:io';

import 'client.dart';

/// Waits for the external platform tree to reflect an already observed fixture
/// state. Native inspect remains necessary for retained entity/selection tests.
Future<Map<String, dynamic>> settingsSemantics(
  int process,
  Map<String, dynamic> observed,
) async {
  final app = observed['app'] as Map;
  final draft = app['draft'] as Map;
  final modal = observed['native']['controls']['reset']['open'] == true;
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  Map<String, dynamic>? last;
  do {
    last = await platformQuery(process);
    final nodes = last['nodes'] as List;
    dynamic byName(String name) => nodes
        .where(
          (n) =>
              n['name'] == name &&
              ![
                'ControlType.Text',
                'AXStaticText',
                'label',
                'static',
              ].contains(n['role']),
        )
        .singleOrNull;
    if (modal) {
      final dialogs = nodes.where(
        (n) =>
            n['name'] == 'Reset preferences?' &&
            (['ControlType.Window', 'dialog'].contains(n['role']) ||
                n['subrole'] == 'AXDialog'),
      );
      if (dialogs.length == 1 &&
          (Platform.isMacOS || dialogs.single['modal'] == true) &&
          byName('Keep editing') != null &&
          byName('Reset draft') != null &&
          byName('General') == null) {
        return last;
      }
    } else if (byName('General') != null && byName('Appearance') != null) {
      if (app['section'] == 'general') {
        final input = byName('Display name');
        final check = byName('Enable workspace notifications');
        if (input != null && check != null) {
          final checked =
              check['checked'] == true ||
              check['checked'] == 'On' ||
              check['value'] == 1 ||
              check['value'] == true;
          final enabled = check['enabled'] == true;
          if (input['value'] == draft['name'] &&
              checked == draft['notifications'] &&
              enabled == (draft['name'] as String).trim().isNotEmpty) {
            return last;
          }
        }
      } else {
        final select = byName('Workspace accent');
        final slider = byName('Preview spacing');
        final expectedAccent = {
          'ocean': 'Ocean',
          'forest': 'Forest',
          'orchid': 'Orchid',
        }[draft['accent']];
        if (select != null &&
            slider != null &&
            (select['value'] ??
                    nodes
                        .where((n) => n['id'] == '["accent","selected-value"]')
                        .singleOrNull?['name']) ==
                expectedAccent &&
            (slider['number'] ?? slider['value']) == draft['spacing'] &&
            slider['min'] == 8 &&
            slider['max'] == 24) {
          return last;
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  } while (DateTime.now().isBefore(deadline));
  throw StateError('Settings semantics did not reflect the fixture: $last');
}
