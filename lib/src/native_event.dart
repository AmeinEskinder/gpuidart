import 'dart:convert';

import 'input_state.dart';
import 'nodes.dart';

/// Validates the native wire format before host state or completers are touched.
Map<String, dynamic> decodeNativeEvent(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > 16 * 1024 * 1024) {
    throw const FormatException('Native event size is invalid');
  }
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Native event must be an object');
  }
  void string(String key) {
    if (value[key] is! String) throw FormatException('Invalid event $key');
  }

  void integer(String key, {int minimum = 0}) {
    if (value[key] is! int || (value[key] as int) < minimum) {
      throw FormatException('Invalid event $key');
    }
  }

  void pendingViews() {
    if (!value.containsKey('pending_views')) return;
    final listed = value['pending_views'];
    if (listed is! List || listed.any((table) => table is! String)) {
      throw const FormatException('Invalid pending views');
    }
  }

  string('type');
  if (value.containsKey('id')) string('id');
  if (value.containsKey('revision')) integer('revision', minimum: 1);
  if (value.containsKey('value')) string('value');
  if (value.containsKey('window')) integer('window', minimum: 1);
  switch (value['type']) {
    case 'ready' || 'closed':
      break;
    case 'applied':
      integer('revision', minimum: 1);
      integer('native_apply_us');
      pendingViews();
    case 'rejected':
      integer('revision', minimum: 1);
      string('message');
    case 'dataset_applied':
      integer('request', minimum: 1);
      integer('revision', minimum: 1);
      string('id');
      integer('parse_us');
      integer('apply_us');
      final work = value['work'];
      if (work is! Map<String, dynamic> ||
          work['records_checked'] is! int ||
          (work['records_checked'] as int) < 0 ||
          work['cells_written'] is! int ||
          (work['cells_written'] as int) < 0) {
        throw const FormatException('Invalid dataset work counters');
      }
      pendingViews();
    case 'table_view':
      integer('revision', minimum: 1);
      string('id');
      string('dataset');
      integer('dataset_revision', minimum: 1);
      integer('view_rows');
      integer('groups');
      integer('compute_us');
    case 'dataset_rejected':
      integer('request', minimum: 1);
      string('message');
    case 'diagnostic':
      integer('request', minimum: 1);
      if (value['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid diagnostic data');
      }
    case 'click' || 'input' || 'table_selection':
      integer('revision', minimum: 1);
      string('id');
      if (value['type'] == 'input') {
        string('value');
        if (value.containsKey('input_state')) {
          final state = decodeInputState(
            value['id'] as String,
            value['input_state'],
          );
          if (!state.controlled || state.value != value['value']) {
            throw const FormatException('Inconsistent controlled input event');
          }
        }
      }
      if (value['type'] == 'table_selection') {
        string('dataset');
        integer('dataset_revision', minimum: 1);
        if (!value.containsKey('row')) {
          throw const FormatException('Missing table selection row');
        }
        if (value['row'] != null) integer('row');
        if (!value.containsKey('record')) {
          throw const FormatException('Missing table selection record');
        }
        if (value['record'] != null) string('record');
      }
    case 'row_action':
      integer('revision', minimum: 1);
      integer('dataset_revision', minimum: 1);
      for (final key in ['id', 'dataset', 'record', 'action']) {
        string(key);
      }
    case 'action':
      integer('revision', minimum: 1);
      string('name');
      string('context');
    case 'checkbox_change' || 'switch_change':
      integer('revision', minimum: 1);
      string('id');
      if (value['checked'] is! bool) {
        throw const FormatException('Invalid toggle checked value');
      }
    case 'list_select':
      integer('revision', minimum: 1);
      string('id');
      string('dataset');
      integer('dataset_revision', minimum: 1);
      integer('row');
      string('record');
    case 'window_opened':
      integer('request', minimum: 1);
      integer('window', minimum: 1);
    case 'window_rejected':
      integer('request', minimum: 1);
      integer('window', minimum: 1);
      string('message');
    case 'window_closed':
      integer('window', minimum: 1);
    case 'slider_change':
      integer('revision', minimum: 1);
      string('id');
      final number = value['number'];
      if (number is! num || !number.isFinite || number.abs() > 1000000) {
        throw const FormatException('Invalid slider number');
      }
    case 'tab_change':
    case 'radio_change':
      integer('revision', minimum: 1);
      string('id');
      string('selected');
    case 'select_change':
      integer('revision', minimum: 1);
      string('id');
      if (!value.containsKey('selected')) {
        throw const FormatException('Missing select selected value');
      }
      if (value['selected'] != null) string('selected');
    case 'tree_select' || 'tree_expand':
      integer('revision', minimum: 1);
      string('id');
      string('item');
      if (value['type'] == 'tree_expand' && value['expanded'] is! bool) {
        throw const FormatException('Missing tree expansion state');
      }
    case 'sheet_close':
      integer('revision', minimum: 1);
      string('id');
    case 'popover_change':
      integer('revision', minimum: 1);
      string('id');
      if (value['open'] is! bool) {
        throw const FormatException('Missing popover open state');
      }
    case 'panes_resize':
      integer('revision', minimum: 1);
      string('id');
      final sizes = value['sizes'];
      if (sizes is! List ||
          sizes.any((size) => size is! num || !size.isFinite || size < 0)) {
        throw const FormatException('Invalid pane sizes');
      }
    case 'date_change':
      integer('revision', minimum: 1);
      string('id');
      if (!value.containsKey('date')) {
        throw const FormatException('Missing date');
      }
      if (value['date'] != null) {
        string('date');
        if (!isCalendarDate(value['date'] as String)) {
          throw const FormatException('Invalid date');
        }
      }
    case 'dialog_result':
      integer('revision', minimum: 1);
      string('id');
      if (value['confirmed'] is! bool) {
        throw const FormatException('Invalid dialog confirmed value');
      }
    case 'input_result':
      integer('request', minimum: 1);
      string('id');
      const statuses = [
        'read',
        'applied',
        'missing',
        'not_controlled',
        'composing',
        'stale',
        'invalid_selection',
      ];
      if (!statuses.contains(value['status']) || !value.containsKey('state')) {
        throw const FormatException('Invalid input acknowledgement');
      }
      if (value['status'] == 'missing') {
        if (value['state'] != null) {
          throw const FormatException('Missing input has state');
        }
      } else {
        decodeInputState(value['id'] as String, value['state']);
      }
    case 'error':
      string('message');
    default:
      throw FormatException('Unknown native event type: ${value['type']}');
  }
  return _freeze(value) as Map<String, dynamic>;
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, dynamic>() => Map<String, dynamic>.unmodifiable(
    value.map((key, value) => MapEntry(key, _freeze(value))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
