part of 'host.dart';

extension InputCommands on GpuiHost {
  /// Samples native value, forward UTF-16 selection and composition state.
  Future<UiInputState> readInput(String id) =>
      _inputCommand(id, {'op': 'read'});

  /// Opt-in controlled write, guarded by [base]'s generation and edit revision.
  /// Native composition rejects writes with `InputWriteException('composing')`.
  /// No write is queued for later. Use a fresh read/event state before retrying.
  /// Replacing text clears native undo history; selection-only writes preserve
  /// it. Writes neither move focus nor echo as user-input events.
  Future<UiInputState> writeInput(
    UiInputState base, {
    String? text,
    UiTextSelection? selection,
  }) {
    validateInputWrite(text, selection);
    return _inputCommand(base.id, {
      'op': 'write',
      'generation': base.generation,
      'base_revision': base.editRevision,
      'text': ?text,
      'selection': ?selection?.toJson(),
    });
  }

  Future<UiInputState> _inputCommand(
    String id,
    Map<String, Object> operation, {
    int window = 0,
  }) {
    if (_closing || _closed.isCompleted) throw StateError('Host is closing');
    if (id.isEmpty) throw ArgumentError.value(id, 'id', 'Must be nonempty');
    final request = ++_request;
    if (window == 0) _trace?._point('dart.request', 'input_control', request);
    final completion = Completer<UiInputState>();
    final status = _withMessage(
      {'request': request, 'id': id, 'operation': operation},
      'input_control',
      request,
      (bytes, length) => window == 0
          ? _bindings.input(_handle, bytes, length)
          : _bindings.windows!.input(_handle, window, bytes, length),
      traced: window == 0,
    );
    if (status != 0) {
      final error = StateError('Input command failed: $status');
      if (status == -4) _fail(error, StackTrace.current);
      throw error;
    }
    _inputPending[request] = (
      id: id,
      expected: operation['op'] == 'read' ? 'read' : 'applied',
      completion: completion,
    );
    return _withDeadline(completion.future, 'input_control $request');
  }
}
