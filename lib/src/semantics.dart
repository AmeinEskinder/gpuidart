import 'dart:convert';

/// Roles that can be assigned to SDK nodes. Interactive roles must match the
/// control's behavior. Dialogs, table rows and cells are generated natively.
enum UiRole {
  group,
  list,
  listItem,
  label,
  heading,
  button,
  checkbox,
  slider,
  textbox,
  combobox,
  table,
  tabList;

  String get wire => switch (this) {
    listItem => 'list_item',
    tabList => 'tab_list',
    _ => name,
  };
}

/// Optional annotations for the native accessibility tree.
///
/// Values, checked/disabled/expanded/selected states, ranges and focus come from
/// the actual control. An annotation cannot override those states independently
/// of its behavior. [label] changes the accessible name, not the visible text.
final class UiSemantics {
  const UiSemantics({this.role, this.label, this.headingLevel});
  final UiRole? role;
  final String? label;
  final int? headingLevel;

  Map<String, Object> toJson(String kind) {
    if (label != null &&
        (label!.isEmpty || utf8.encode(label!).length > 1024)) {
      throw ArgumentError('Semantics label must contain 1..1024 UTF-8 bytes');
    }
    final allowed = switch (kind) {
      'row' || 'column' => {UiRole.group, UiRole.list, UiRole.listItem},
      'text' => {UiRole.label, UiRole.heading},
      'button' || 'confirm_dialog' => {UiRole.button},
      'checkbox' => {UiRole.checkbox},
      'slider' => {UiRole.slider},
      'input' => {UiRole.textbox},
      'select' => {UiRole.combobox},
      'table' => {UiRole.table},
      'tabs' => {UiRole.tabList},
      _ => throw ArgumentError.value(kind, 'kind'),
    };
    if (role != null && !allowed.contains(role)) {
      throw ArgumentError(
        'Semantics role ${role!.wire} is incompatible with $kind',
      );
    }
    if ((role == UiRole.heading) != (headingLevel != null) ||
        (headingLevel != null && (headingLevel! < 1 || headingLevel! > 6))) {
      throw ArgumentError('Heading role requires a level from 1 through 6');
    }
    return {
      if (role != null) 'role': role!.wire,
      'label': ?label,
      'heading_level': ?headingLevel,
    };
  }
}
