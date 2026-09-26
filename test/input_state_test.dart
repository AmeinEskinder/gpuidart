import 'dart:convert';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/input_state.dart';
import 'package:gpuidart/src/native_event.dart';
import 'package:test/test.dart';

void main() {
  final state = <String, Object?>{
    'generation': 1,
    'edit_revision': 2,
    'controlled': true,
    'value': 'A😀日',
    'selection': {'start': 1, 'end': 3},
    'composing': false,
  };
  test('controlled mode is opt-in and UTF-16 state is immutable', () {
    expect(const UiInput('name').toJson().containsKey('controlled'), false);
    expect(
      const UiInput('name', controlled: true).toJson()['controlled'],
      true,
    );
    final decoded = decodeInputState('name', state);
    expect(decoded.id, 'name');
    expect(decoded.value, 'A😀日');
    expect(decoded.selection.start, 1);
    expect(decoded.selection.end, 3);
    expect(decoded.generation, 1);
    expect(decoded.editRevision, 2);
  });
  test('writes validate scalar boundaries, size and required content', () {
    validateInputWrite('A😀日', const UiTextSelection(1, 3));
    validateInputWrite(null, const UiTextSelection(0, 3));
    validateInputWrite('x' * (1024 * 1024), null);
    for (final (text, selection) in <(String?, UiTextSelection?)>[
      (null, null),
      ('A😀日', const UiTextSelection(2, 2)),
      ('A😀日', const UiTextSelection(0, 5)),
      ('x', const UiTextSelection(-1, 0)),
      (null, const UiTextSelection(2, 1)),
      ('\ud800', null),
      ('x' * (1024 * 1024 + 1), null),
    ]) {
      expect(() => validateInputWrite(text, selection), throwsArgumentError);
    }
  });
  test(
    'malformed states and inconsistent acknowledgements fail at the boundary',
    () {
      Map<String, dynamic> decode(Object? value) =>
          decodeNativeEvent(utf8.encode(jsonEncode(value)));
      final reply = <String, Object?>{
        'type': 'input_result',
        'request': 1,
        'id': 'name',
        'status': 'applied',
        'state': state,
      };
      expect(decode(reply)['state'], state);
      for (final bad in [
        {...state, 'generation': 0},
        {...state, 'edit_revision': -1},
        {...state, 'controlled': 1},
        {...state, 'composing': 'false'},
        {...state, 'value': 1},
        {
          ...state,
          'selection': {'start': 2, 'end': 2},
        },
        {
          ...state,
          'selection': {'start': 0, 'end': 5},
        },
      ]) {
        expect(() => decode({...reply, 'state': bad}), throwsFormatException);
      }
      for (final bad in [
        {...reply, 'state': null},
        {...reply, 'status': 'unknown'},
        {...reply, 'status': 'missing'},
        {
          'type': 'input_result',
          'request': 1,
          'id': 'name',
          'status': 'applied',
        },
        {
          'type': 'input',
          'id': 'name',
          'revision': 1,
          'value': 'wrong',
          'input_state': state,
        },
      ]) {
        expect(() => decode(bad), throwsFormatException);
      }
      expect(
        decode({...reply, 'status': 'missing', 'state': null})['state'],
        isNull,
      );
      expect(
        decode({
          'type': 'input',
          'id': 'name',
          'revision': 1,
          'value': 'A😀日',
          'input_state': state,
        })['input_state'],
        state,
      );
    },
  );
}
