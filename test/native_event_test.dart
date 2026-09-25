import 'dart:convert';

import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

Map<String, dynamic> decode(Object? value) =>
    decodeNativeEvent(utf8.encode(jsonEncode(value)));

void main() {
  test('rejects invalid UTF-8, JSON, envelopes and required field types', () {
    for (final bytes in [
      <int>[],
      [0xff],
      utf8.encode('{'),
    ]) {
      expect(() => decodeNativeEvent(bytes), throwsFormatException);
    }
    for (final value in <Object?>[
      null,
      [],
      'ready',
      {},
      {'type': 'unknown'},
      {'type': 'applied', 'revision': '2', 'native_apply_us': 0},
      {'type': 'applied', 'revision': 2, 'native_apply_us': -1},
      {'type': 'input', 'revision': 2, 'id': 'input', 'value': 1},
      {'type': 'diagnostic', 'request': 1, 'data': []},
      {
        'type': 'dataset_applied',
        'request': 1,
        'revision': 2,
        'id': 'records',
        'parse_us': 0,
        'apply_us': 0,
        'work': {'records_checked': 1, 'cells_written': '1'},
      },
      {
        'type': 'table_selection',
        'revision': 2,
        'id': 'table',
        'dataset': 'records',
        'dataset_revision': 1,
        'row': -1,
      },
    ]) {
      expect(() => decode(value), throwsFormatException, reason: '$value');
    }
  });

  test(
    'preserves Unicode and tracing fields; decoded events are immutable',
    () {
      final event = decode({
        'type': 'input',
        'revision': 2,
        'id': 'name',
        'value': '日本語 🦀',
        'trace': {
          'points': [1, 2],
        },
      });
      expect(event['value'], '日本語 🦀');
      expect(event['trace']['points'], [1, 2]);
      expect(() => event['value'] = 'changed', throwsUnsupportedError);
      expect(() => event['trace']['points'].add(3), throwsUnsupportedError);
      expect(
        decode({
          'type': 'table_selection',
          'revision': 2,
          'id': 'table',
          'dataset': 'records',
          'dataset_revision': 1,
          'row': null,
        })['row'],
        isNull,
      );
    },
  );
}
