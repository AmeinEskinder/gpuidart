import 'dart:convert';

/// Forward selection offsets in UTF-16 code units, as used by Dart strings.
final class UiTextSelection {
  const UiTextSelection(this.start, this.end);
  final int start;
  final int end;
  Map<String, Object> toJson() {
    if (start < 0 || end < start) {
      throw ArgumentError('Invalid input selection');
    }
    return {'start': start, 'end': end};
  }
}

/// An acknowledged native input state. Pass this state to `writeInput` to
/// prevent a delayed application write from replacing a newer native edit.
final class UiInputState {
  const UiInputState._(
    this.id,
    this.generation,
    this.editRevision,
    this.controlled,
    this.value,
    this.selection,
    this.composing,
  );
  final String id;
  final int generation;
  final int editRevision;
  final bool controlled;
  final String value;
  final UiTextSelection selection;
  final bool composing;
}

/// A rejected application write. [current] is the native state at rejection;
/// null means the input no longer exists. Rejections do not close the host.
final class InputWriteException implements Exception {
  const InputWriteException(this.reason, this.current);
  final String reason;
  final UiInputState? current;
  @override
  String toString() => 'Input write rejected: $reason';
}

UiInputState decodeInputState(String id, Object? data) {
  if (data is! Map<String, dynamic> ||
      data['generation'] is! int ||
      (data['generation'] as int) < 1 ||
      data['edit_revision'] is! int ||
      (data['edit_revision'] as int) < 0 ||
      data['controlled'] is! bool ||
      data['composing'] is! bool ||
      data['value'] is! String) {
    throw const FormatException('Invalid native input state');
  }
  final selection = data['selection'];
  final text = data['value'] as String;
  if (selection is! Map<String, dynamic> ||
      selection['start'] is! int ||
      selection['end'] is! int ||
      !validSelection(
        text,
        selection['start'] as int,
        selection['end'] as int,
      )) {
    throw const FormatException('Invalid native UTF-16 selection');
  }
  return UiInputState._(
    id,
    data['generation'] as int,
    data['edit_revision'] as int,
    data['controlled'] as bool,
    text,
    UiTextSelection(selection['start'] as int, selection['end'] as int),
    data['composing'] as bool,
  );
}

bool validSelection(String text, int start, int end) {
  bool boundary(int offset) =>
      offset == 0 ||
      offset == text.length ||
      !(text.codeUnitAt(offset - 1) >= 0xd800 &&
          text.codeUnitAt(offset - 1) <= 0xdbff &&
          text.codeUnitAt(offset) >= 0xdc00 &&
          text.codeUnitAt(offset) <= 0xdfff);
  return start >= 0 &&
      end >= start &&
      end <= text.length &&
      boundary(start) &&
      boundary(end);
}

void validateInputWrite(String? text, UiTextSelection? selection) {
  if (text == null && selection == null) {
    throw ArgumentError('Write text and/or selection');
  }
  selection?.toJson();
  if (text != null) {
    if (utf8.encode(text).length > 1024 * 1024 ||
        text.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
      throw ArgumentError('Text must be valid Unicode, at most 1 MiB UTF-8');
    }
    if (selection != null &&
        !validSelection(text, selection.start, selection.end)) {
      throw ArgumentError('Selection splits a surrogate pair or exceeds text');
    }
  }
}
