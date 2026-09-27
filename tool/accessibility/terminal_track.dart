import 'dart:convert';
import 'dart:io';

import 'client.dart';

dynamic _find(List nodes, String id) =>
    nodes.where((n) => n['id'] == id).singleOrNull;
bool _role(dynamic node, List<String> roles) =>
    node != null && roles.contains(node['role']);
bool _selected(dynamic node) =>
    node != null &&
    (node['selected'] == true ||
        node['checked'] == true ||
        node['checked'] == 'On' ||
        node['value'] == 1);
bool _tooltip(dynamic node) =>
    _role(node, ['ControlType.ToolTip', 'AXHelpTag', 'tool tip']);
bool _menu(dynamic node) => _role(node, ['ControlType.Menu', 'AXMenu', 'menu']);
bool _item(dynamic node) => _role(node, [
  'ControlType.MenuItem',
  'AXMenuItem',
  'menu item',
  'check menu item',
  'radio menu item',
]);

Future<Map<String, dynamic>> _wait(
  int process,
  String step,
  bool Function(List) ready,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  Map<String, dynamic>? last;
  do {
    last = await platformQuery(process);
    if (ready(last['nodes'] as List)) return last;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  } while (DateTime.now().isBefore(deadline));
  throw StateError(
    'External terminal tree did not settle ($step): ${jsonEncode(last)}',
  );
}

Future<Map<String, dynamic>> terminalSemantics(
  int process,
  Map<String, dynamic> observed,
) {
  final app = observed['app'] as Map;
  final native = observed['native'] as Map;
  return _wait(process, '${app['page']} state', (nodes) {
    final tabs = _find(nodes, 'pages');
    if (!_role(tabs, ['ControlType.Tab', 'AXTabGroup', 'page tab list']) ||
        tabs['name'] != 'Terminal pages')
      return false;
    for (final page in ['watchlist', 'instrument', 'settings']) {
      final node = _find(nodes, jsonEncode(['pages', 'tab', page]));
      if (!_role(node, ['ControlType.TabItem', 'AXRadioButton', 'page tab']) ||
          _selected(node) != (app['page'] == page))
        return false;
    }
    if (app['page'] == 'watchlist') {
      final search = _find(nodes, 'search');
      return hasPlatformRole(_find(nodes, 'watchlist'), 'table') &&
          hasPlatformRole(search, 'input') &&
          search['value'] == native['inputs']['search']['text'] &&
          _find(nodes, 'tick')?['description'] ==
              'Update the selected sample price by 0.07';
    }
    if (app['page'] == 'settings') {
      final name = _find(nodes, 'display-name');
      if (!hasPlatformRole(name, 'input') ||
          name['value'] != app['display_name'])
        return false;
      for (final mode in ['light', 'dark']) {
        final radio = _find(nodes, jsonEncode(['theme', 'radio', mode]));
        if (!_role(radio, [
              'ControlType.RadioButton',
              'AXRadioButton',
              'radio button',
            ]) ||
            _selected(radio) != (app['theme'] == mode))
          return false;
      }
      final accent = _find(nodes, 'custom-accent');
      return hasPlatformRole(accent, 'checkbox') &&
          _selected(accent) == app['custom_accent'];
    }
    if (app['selected'] == null)
      return _find(nodes, 'empty-instrument') != null;
    for (final chart in ['price-chart', 'volume-chart']) {
      final state = native['charts'][chart];
      final summary = _find(nodes, jsonEncode([chart, 'summary']));
      if (_find(nodes, chart) == null ||
          (summary?['value'] ?? summary?['name']) != state['summary'])
        return false;
      for (final point in state['points'] as List) {
        final node = _find(
          nodes,
          jsonEncode([chart, 'history', point['record']]),
        );
        final text = '${point['label']}: ${_number(point['value'] as num)}';
        if ((node?['value'] ?? node?['name']) != text) return false;
      }
    }
    final radio = _find(nodes, jsonEncode(['period', 'radio', app['period']]));
    return _role(radio, [
          'ControlType.RadioButton',
          'AXRadioButton',
          'radio button',
        ]) &&
        _selected(radio);
  });
}

String _number(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

Future<Map<String, Object?>> verifyTerminalTooltip(int process) async {
  await platformQuery(process, operation: 'hover', id: 'tick');
  final appeared = await _wait(
    process,
    'hover popup',
    (nodes) =>
        nodes.any(_tooltip) &&
        _find(nodes, 'tick')?['name'] == 'Simulate price update',
  );
  await platformQuery(process, operation: 'hover', id: 'search');
  final dismissed = await _wait(
    process,
    'tooltip dismissal',
    (nodes) => !nodes.any(_tooltip),
  );
  return {
    'source': 'OS pointer movement to external accessibility bounds',
    'appeared': appeared,
    'dismissed': dismissed,
  };
}

Future<Map<String, dynamic>> terminalMenuSemantics(
  int process, {
  bool context = false,
}) => _wait(
  process,
  context ? 'row context menu' : 'application menu',
  (nodes) =>
      nodes.any(_menu) &&
      nodes.any(
        (n) =>
            _item(n) && n['name'] == (context ? 'Open instrument' : 'Settings'),
      ),
);

Future<Map<String, Object?>> invokeTerminalSettingsMenu(int process) async {
  final bar = await _wait(
    process,
    'application menu bar',
    (nodes) => nodes.any(
      (n) => _role(n, ['ControlType.MenuBar', 'AXMenuBar', 'menu bar']),
    ),
  );
  Map<String, dynamic> opened;
  if (Platform.isMacOS) {
    // The native app menu may use the executable's name. Its Settings child
    // identifies the owned command without assuming the app bundle name.
    opened = await terminalMenuSemantics(process);
  } else {
    await platformQuery(process, operation: 'invoke', name: 'Terminal');
    opened = await terminalMenuSemantics(process);
  }
  final action = await platformQuery(
    process,
    operation: 'invoke-menu',
    name: 'Settings',
  );
  return {
    'native_app_menu': Platform.isMacOS,
    'bar': bar,
    'opened': opened,
    'action': action,
  };
}
