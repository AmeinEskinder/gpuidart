import 'dart:convert';

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

  string('type');
  if (value.containsKey('id')) string('id');
  if (value.containsKey('revision')) integer('revision', minimum: 1);
  if (value.containsKey('value')) string('value');
  switch (value['type']) {
    case 'ready' || 'closed':
      break;
    case 'applied':
      integer('revision', minimum: 1);
      integer('native_apply_us');
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
      if (value['type'] == 'input') string('value');
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
    case 'action':
      integer('revision', minimum: 1);
      string('name');
      string('context');
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
