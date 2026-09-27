import 'dart:convert';
import 'dart:typed_data';

import 'style.dart';
import 'menus.dart';
import 'semantics.dart';
import 'table_view.dart';

sealed class UiNode {
  const UiNode(this.id, {this.style, this.semantics});
  final String id;
  final UiStyle? style;
  final UiSemantics? semantics;
  Map<String, Object> toJson();
}

final class UiColumn extends UiNode {
  UiColumn(super.id, List<UiNode> children, {super.style, super.semantics})
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'column',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('column'),
    if (style != null) 'style': style!.toJson(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// A horizontal group that wraps to another line when the window is narrow.
final class UiRow extends UiNode {
  UiRow(super.id, List<UiNode> children, {super.style, super.semantics})
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'row',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('row'),
    if (style != null) 'style': style!.toJson(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

final class UiText extends UiNode {
  const UiText(super.id, this.text, {super.style, super.semantics});
  final String text;
  @override
  Map<String, Object> toJson() => {
    'kind': 'text',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('text'),
    if (style != null) 'style': style!.toJson(),
    'text': text,
  };
}

final class UiButton extends UiNode {
  const UiButton(super.id, this.label, {super.style, super.semantics});
  final String label;
  @override
  Map<String, Object> toJson() => {
    'kind': 'button',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('button'),
    if (style != null) 'style': style!.toJson(),
    'label': label,
  };
}

/// A controlled checkbox. Publish the requested [GpuiEvent.checked] value to
/// acknowledge a `checkbox_change` event. Disabled checkboxes are not tab stops.
final class UiCheckbox extends UiNode {
  const UiCheckbox(
    super.id,
    this.label, {
    required this.checked,
    this.disabled = false,
    super.style,
    super.semantics,
  });
  final String label;
  final bool checked;
  final bool disabled;

  @override
  Map<String, Object> toJson() {
    if (utf8.encode(label).length > 1024) {
      throw ArgumentError.value(label, 'label', 'Maximum 1024 UTF-8 bytes');
    }
    return {
      'kind': 'checkbox',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('checkbox'),
      if (style != null) 'style': style!.toJson(),
      'label': label,
      'checked': checked,
      'disabled': disabled,
    };
  }
}

/// A single-value, linear native slider. Values use native 32-bit precision.
/// Publish `slider_change` event.number to accept an edit. Arrows step by
/// [step]; Home and End choose the range endpoints. Pointer values snap to
/// multiples of [step] and clamp to the endpoints.
final class UiSlider extends UiNode {
  const UiSlider(
    super.id, {
    required this.min,
    required this.max,
    required this.step,
    required this.number,
    this.disabled = false,
    super.style,
    super.semantics,
  });
  final double min;
  final double max;
  final double step;
  final double number;
  final bool disabled;

  @override
  Map<String, Object> toJson() {
    final native = Float32List.fromList([min, max, step, number]);
    final stepped = Float32List.fromList([
      native[0] + native[2],
      native[1] - native[2],
    ]);
    if (!native.every((v) => v.isFinite) ||
        min.abs() > 1000000 ||
        max.abs() > 1000000 ||
        min >= max ||
        step <= 0 ||
        step > max - min ||
        stepped[0] <= native[0] ||
        stepped[1] >= native[1] ||
        number < min ||
        number > max) {
      throw ArgumentError('Invalid slider range, step or number');
    }
    return {
      'kind': 'slider',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('slider'),
      if (style != null) 'style': style!.toJson(),
      'min': min,
      'max': max,
      'step': step,
      'number': number,
      'disabled': disabled,
    };
  }
}

/// A stable select identity with a separately editable display label.
final class UiSelectOption {
  const UiSelectOption(this.id, this.label);
  final String id;
  final String label;
  Map<String, Object> toJson() => {'id': id, 'label': label};
}

/// A native dropdown. Publish `select_change` event.selected to accept a choice.
/// A null selection displays [placeholder]. Option order and labels can change
/// without changing the selected identity. Unchanged snapshots retain the menu.
final class UiSelect extends UiNode {
  UiSelect(
    super.id, {
    required List<UiSelectOption> options,
    this.selected,
    this.placeholder = '',
    this.disabled = false,
    super.style,
    super.semantics,
  }) : options = List.unmodifiable(options);
  final List<UiSelectOption> options;
  final String? selected;
  final String placeholder;
  final bool disabled;

  @override
  Map<String, Object> toJson() {
    if (options.isEmpty ||
        options.length > 256 ||
        utf8.encode(placeholder).length > 1024) {
      throw ArgumentError(
        'Select requires 1..256 options and a placeholder of at most 1024 UTF-8 bytes',
      );
    }
    final ids = <String>{};
    for (final option in options) {
      if (option.id.isEmpty ||
          utf8.encode(option.id).length > 256 ||
          !ids.add(option.id) ||
          option.label.isEmpty ||
          utf8.encode(option.label).length > 1024) {
        throw ArgumentError('Invalid or duplicate select option');
      }
    }
    if (selected != null && !ids.contains(selected)) {
      throw ArgumentError.value(selected, 'selected', 'Not an option ID');
    }
    return {
      'kind': 'select',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('select'),
      if (style != null) 'style': style!.toJson(),
      'options': options.map((o) => o.toJson()).toList(),
      'selected': ?selected,
      'placeholder': placeholder,
      'disabled': disabled,
    };
  }
}

/// A button that opens a native confirmation dialog. [style] applies to the
/// trigger; the modal uses the current native theme. The opening description
/// stays visible until dismissal. A `dialog_result` event reports confirmation
/// or cancellation once. Disabling/removing this node cancels an open dialog.
final class UiConfirmDialog extends UiNode {
  const UiConfirmDialog(
    super.id,
    this.label, {
    required this.title,
    required this.message,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.disabled = false,
    super.style,
    super.semantics,
  });
  final String label;
  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool disabled;
  @override
  Map<String, Object> toJson() {
    if ([
          label,
          title,
          confirmLabel,
          cancelLabel,
        ].any((s) => s.isEmpty || utf8.encode(s).length > 1024) ||
        utf8.encode(message).length > 8192) {
      throw ArgumentError(
        'Dialog labels must contain 1..1024 UTF-8 bytes; message at most 8192',
      );
    }
    return {
      'kind': 'confirm_dialog',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('confirm_dialog'),
      if (style != null) 'style': style!.toJson(),
      'label': label,
      'title': title,
      'message': message,
      'confirm_label': confirmLabel,
      'cancel_label': cancelLabel,
      'disabled': disabled,
    };
  }
}

/// Native text, cursor, selection and undo state survive snapshots with this ID.
final class UiInput extends UiNode {
  const UiInput(
    super.id, {
    super.style,
    super.semantics,
    this.placeholder = '',
    this.controlled = false,
  });
  final String placeholder;
  final bool controlled;
  @override
  Map<String, Object> toJson() => {
    'kind': 'input',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('input'),
    if (style != null) 'style': style!.toJson(),
    'placeholder': placeholder,
    if (controlled) 'controlled': true,
  };
}

/// References a dataset registered with this host. Snapshots contain no records.
final class UiTable extends UiNode {
  const UiTable(
    super.id, {
    super.style,
    super.semantics,
    required this.dataset,
    this.view,
    this.contextMenu = const [],
  });
  final String dataset;

  /// Presentation-only sort/filter view over the dataset.
  final UiTableView? view;

  /// Row commands require dataset record IDs. Right-click or Shift+F10 opens.
  final List<UiMenuEntry> contextMenu;
  @override
  Map<String, Object> toJson() => {
    'kind': 'table',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('table'),
    if (style != null) 'style': style!.toJson(),
    'dataset': dataset,
    if (view != null) 'view': view!.toJson(),
    if (contextMenu.isNotEmpty) 'context_menu': _encodeContextMenu(contextMenu),
  };
}

/// A stable choice identity with a separate display label and enabled state.
final class UiChoiceOption {
  const UiChoiceOption(this.id, this.label, {this.disabled = false});
  final String id;
  final String label;
  final bool disabled;
  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'disabled': disabled,
  };
}

void _validateChoices(List<UiChoiceOption> options, String selected) {
  if (options.isEmpty || options.length > 32) {
    throw ArgumentError('Choice groups require 1..32 options');
  }
  final ids = <String>{};
  for (final option in options) {
    if (option.id.isEmpty ||
        utf8.encode(option.id).length > 256 ||
        !ids.add(option.id) ||
        option.label.isEmpty ||
        utf8.encode(option.label).length > 1024) {
      throw ArgumentError('Invalid or duplicate choice option');
    }
  }
  if (!options.any((o) => o.id == selected && !o.disabled)) {
    throw ArgumentError('Selected choice must be an enabled option');
  }
}

/// A tab strip. The application publishes the active page as a separate node.
/// Arrows/Home/End move focus; Enter/Space activate. Publish the requested
/// `tab_change` event.selected to accept a choice. Only one tab is a tab stop.
final class UiTabs extends UiNode {
  UiTabs(
    super.id, {
    required List<UiChoiceOption> options,
    required this.selected,
    this.disabled = false,
    super.style,
    super.semantics,
  }) : options = List.unmodifiable(options);
  final List<UiChoiceOption> options;
  final String selected;
  final bool disabled;
  @override
  Map<String, Object> toJson() {
    _validateChoices(options, selected);
    return {
      'kind': 'tabs',
      'id': id,
      'options': options.map((o) => o.toJson()).toList(),
      'selected': selected,
      'disabled': disabled,
      if (style != null) 'style': style!.toJson(),
      if (semantics != null) 'semantics': semantics!.toJson('tabs'),
    };
  }
}

List<Map<String, Object>> _encodeContextMenu(List<UiMenuEntry> entries) {
  validateMenuEntries(entries);
  return entries.map((entry) => entry.toJson()).toList();
}
