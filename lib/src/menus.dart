import 'dart:convert';

/// One flat native application menu. Entries reference global [UiAction] names.
final class UiMenu {
  UiMenu(this.id, this.label, List<UiMenuEntry> items)
    : items = List.unmodifiable(items);
  final String id;
  final String label;
  final List<UiMenuEntry> items;
  Map<String, Object> toJson() {
    _bounded(id, 256, 'menu ID');
    _bounded(label, 1024, 'menu label');
    validateMenuEntries(items);
    return {
      'id': id,
      'label': label,
      'items': items.map((entry) => entry.toJson()).toList(),
    };
  }
}

sealed class UiMenuEntry {
  const UiMenuEntry();
  Map<String, Object> toJson();
}

final class UiMenuSeparator extends UiMenuEntry {
  const UiMenuSeparator();
  @override
  Map<String, Object> toJson() => {'kind': 'separator'};
}

final class UiMenuAction extends UiMenuEntry {
  const UiMenuAction(
    this.id,
    this.label, {
    required this.action,
    this.checked = false,
    this.disabled = false,
  });
  final String id;
  final String label;
  final String action;
  final bool checked;
  final bool disabled;
  @override
  Map<String, Object> toJson() {
    _bounded(id, 256, 'entry ID');
    _bounded(label, 1024, 'entry label');
    _bounded(action, 256, 'action');
    return {
      'kind': 'action',
      'id': id,
      'label': label,
      'action': action,
      'checked': checked,
      'disabled': disabled,
    };
  }
}

void _bounded(String value, int limit, String name) {
  if (value.isEmpty || utf8.encode(value).length > limit) {
    throw ArgumentError('$name requires 1..$limit UTF-8 bytes');
  }
}

void validateMenuEntries(List<UiMenuEntry> items) {
  if (items.isEmpty || items.length > 64) {
    throw ArgumentError('Menus require 1..64 entries');
  }
  final ids = <String>{};
  for (final item in items) {
    item.toJson();
    if (item is UiMenuAction && !ids.add(item.id)) {
      throw ArgumentError('Duplicate menu entry ID');
    }
  }
}

List<Map<String, Object>> encodeMenus(List<UiMenu> menus) {
  if (menus.length > 8) {
    throw ArgumentError('At most 8 application menus are supported');
  }
  final ids = <String>{};
  return menus.map((menu) {
    if (!ids.add(menu.id)) throw ArgumentError('Duplicate application menu ID');
    return menu.toJson();
  }).toList();
}
