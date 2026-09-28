/// Keeps a built value while its inputs stay equal, so a rebuild hands the
/// host the same [UiNode] instance for an unchanged part of the screen and
/// the description and diff skip it. Const nodes get the same treatment
/// without a memo.
///
/// ```dart
/// final header = UiMemo<UiNode>();
/// UiNode build() => UiColumn('root', [
///   header.of([title, unread], () => UiRow('header', [...])),
///   UiText('status', status),
/// ]);
/// ```
final class UiMemo<T extends Object> {
  List<Object?>? _inputs;
  T? _value;

  /// The value built for [inputs]; [build] runs only when an input changed
  /// by `==` since the last call.
  T of(List<Object?> inputs, T Function() build) {
    final previous = _inputs;
    final value = _value;
    if (previous != null && value != null && _sameInputs(previous, inputs)) {
      return value;
    }
    final built = build();
    _inputs = List.unmodifiable(inputs);
    _value = built;
    return built;
  }

  /// Forgets the kept value so the next call builds again.
  void reset() {
    _inputs = null;
    _value = null;
  }
}

bool _sameInputs(List<Object?> a, List<Object?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
