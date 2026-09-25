/// A scoped key binding declared by the application. When `keys` is pressed
/// while focus is inside `context`, the native host emits an `action` event
/// with this binding's `name` and `context`. No native command execution
/// happens; the event is the whole contract.
///
/// `keys` grammar: modifiers `ctrl|alt|shift|meta` plus one key (letters,
/// digits, f1–f12, enter, escape, space, tab, arrows, home/end/pageup/
/// pagedown, delete, backspace), joined with `+` (e.g. `ctrl+enter`).
/// Modifiers are literal: `ctrl` is always the control key and `meta` is the
/// platform meta key (cmd on macOS, windows key on Windows, super on Linux) —
/// apps declare per-platform bindings themselves. Bare letters and digits
/// with no modifier are rejected: native text input and IME own them.
final class UiAction {
  const UiAction({
    required this.name,
    required this.keys,
    this.context = const UiActionContext.global(),
  });

  /// Dotted action name, e.g. `watchlist.add`.
  final String name;

  /// Key binding, e.g. `ctrl+f`.
  final String keys;

  /// Scope: [UiActionContext.global] or a node ID from the same snapshot.
  final UiActionContext context;

  Map<String, Object> toJson() {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must be nonempty');
    }
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'must be nonempty');
    }
    return {'name': name, 'keys': keys, 'context': context.toJson()};
  }
}

/// Where an action binding applies. Dispatch walks from the focused node up
/// the snapshot tree; the innermost context with a matching binding wins and
/// `global` matches last.
sealed class UiActionContext {
  const UiActionContext._();

  const factory UiActionContext.global() = UiGlobalActionContext;

  /// Scopes the binding to a node ID present in the same snapshot.
  const factory UiActionContext.node(String id) = UiNodeActionContext;

  String toJson();
}

final class UiGlobalActionContext extends UiActionContext {
  const UiGlobalActionContext() : super._();
  @override
  String toJson() => 'global';
}

final class UiNodeActionContext extends UiActionContext {
  const UiNodeActionContext(this.id) : super._();
  final String id;
  @override
  String toJson() {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must be nonempty');
    }
    return id;
  }
}
