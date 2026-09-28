import 'dart:convert';
import 'dart:typed_data';

import 'style.dart';
import 'menus.dart';
import 'semantics.dart';
import 'table_view.dart';

part 'charts.dart';

sealed class UiNode {
  const UiNode(this.id, {this.style, this.semantics});
  final String id;
  final UiStyle? style;
  final UiSemantics? semantics;

  /// Child nodes. Only container kinds have any.
  List<UiNode> get children => const [];

  /// Whether this kind carries children on the wire.
  bool get isContainer => false;

  /// This node's own fields without [children]. Throws [ArgumentError] when a
  /// field is outside the protocol's bounds.
  Map<String, Object> props();

  /// The complete description of this node and its descendants.
  Map<String, Object> toJson() => props();
}

final class UiColumn extends UiNode {
  UiColumn(super.id, List<UiNode> children, {super.style, super.semantics})
    : children = List.unmodifiable(children);
  @override
  final List<UiNode> children;
  @override
  bool get isContainer => true;
  @override
  Map<String, Object> props() => {
    'kind': 'column',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('column'),
    if (style != null) 'style': style!.toJson(),
  };
  @override
  Map<String, Object> toJson() => {
    ...props(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// A horizontal group that wraps to another line when the window is narrow.
final class UiRow extends UiNode {
  UiRow(super.id, List<UiNode> children, {super.style, super.semantics})
    : children = List.unmodifiable(children);
  @override
  final List<UiNode> children;
  @override
  bool get isContainer => true;
  @override
  Map<String, Object> props() => {
    'kind': 'row',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('row'),
    if (style != null) 'style': style!.toJson(),
  };
  @override
  Map<String, Object> toJson() => {
    ...props(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// Children overlap in order. A child sits at the top left with its own size
/// unless its style has an [UiInset]; `UiSize.full` width and height cover the
/// stack. Give the stack a size through its style or its parent.
final class UiStack extends UiNode {
  UiStack(super.id, List<UiNode> children, {super.style, super.semantics})
    : children = List.unmodifiable(children);
  @override
  final List<UiNode> children;
  @override
  bool get isContainer => true;
  @override
  Map<String, Object> props() => {
    'kind': 'stack',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('stack'),
    if (style != null) 'style': style!.toJson(),
  };
  @override
  Map<String, Object> toJson() => {
    ...props(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

enum UiScrollAxis {
  vertical('vertical'),
  horizontal('horizontal'),
  both('both');

  const UiScrollAxis(this.wire);
  final String wire;
}

/// A bounded container whose content scrolls. Bound it through its style or a
/// flex parent; the scroll offset is retained by ID across publications.
final class UiScroll extends UiNode {
  UiScroll(
    super.id,
    List<UiNode> children, {
    this.axis = UiScrollAxis.vertical,
    super.style,
    super.semantics,
  }) : children = List.unmodifiable(children);
  final UiScrollAxis axis;
  @override
  final List<UiNode> children;
  @override
  bool get isContainer => true;
  @override
  Map<String, Object> props() => {
    'kind': 'scroll',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('scroll'),
    if (style != null) 'style': style!.toJson(),
    if (axis != UiScrollAxis.vertical) 'axis': axis.wire,
  };
  @override
  Map<String, Object> toJson() => {
    ...props(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

final class UiText extends UiNode {
  const UiText(super.id, this.text, {super.style, super.semantics});
  final String text;
  @override
  Map<String, Object> props() => {
    'kind': 'text',
    'id': id,
    if (semantics != null) 'semantics': semantics!.toJson('text'),
    if (style != null) 'style': style!.toJson(),
    'text': text,
  };
}

/// A native button. [tooltip] supplies hover help and its accessible description.
final class UiButton extends UiNode {
  const UiButton(
    super.id,
    this.label, {
    this.tooltip,
    super.style,
    super.semantics,
  });
  final String label;
  final String? tooltip;
  @override
  Map<String, Object> props() {
    if (tooltip != null &&
        (tooltip!.isEmpty || utf8.encode(tooltip!).length > 1024)) {
      throw ArgumentError.value(
        tooltip,
        'tooltip',
        'Requires 1..1024 UTF-8 bytes',
      );
    }
    return {
      'kind': 'button',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('button'),
      if (style != null) 'style': style!.toJson(),
      'label': label,
      'tooltip': ?tooltip,
    };
  }
}

/// An on/off toggle. Publish the requested [GpuiEvent.checked] value to
/// acknowledge a `switch_change` event; the switch shows the toggle at once.
final class UiSwitch extends UiNode {
  const UiSwitch(
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
  Map<String, Object> props() {
    if (utf8.encode(label).length > 1024) {
      throw ArgumentError.value(label, 'label', 'Maximum 1024 UTF-8 bytes');
    }
    return {
      'kind': 'switch',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('switch'),
      if (style != null) 'style': style!.toJson(),
      'label': label,
      'checked': checked,
      'disabled': disabled,
    };
  }
}

/// A progress bar. [value] is a percentage 0–100; null shows an indeterminate
/// bar.
final class UiProgress extends UiNode {
  const UiProgress(super.id, {this.value, super.style, super.semantics});
  final double? value;

  @override
  Map<String, Object> props() {
    final value = this.value;
    if (value != null && (!value.isFinite || value < 0 || value > 100)) {
      throw ArgumentError.value(value, 'value', 'Progress is 0..100');
    }
    return {
      'kind': 'progress',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('progress'),
      if (style != null) 'style': style!.toJson(),
      'value': ?value,
    };
  }
}

/// A horizontal or vertical rule with an optional centered label.
final class UiSeparator extends UiNode {
  const UiSeparator(
    super.id, {
    this.vertical = false,
    this.label = '',
    super.style,
    super.semantics,
  });
  final bool vertical;
  final String label;

  @override
  Map<String, Object> props() {
    if (utf8.encode(label).length > 1024) {
      throw ArgumentError.value(label, 'label', 'Maximum 1024 UTF-8 bytes');
    }
    return {
      'kind': 'separator',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('separator'),
      if (style != null) 'style': style!.toJson(),
      'vertical': vertical,
      if (label.isNotEmpty) 'label': label,
    };
  }
}

/// A virtualized list over one column of a registered dataset. Items follow
/// the optional [view] (filter and sort; lists do not group) and the dataset
/// must carry record IDs. A click reports `list_select` with the record in
/// [GpuiEvent.listSelection]; the item shows the pick at once and the next
/// publication's [selected] record is authoritative.
final class UiList extends UiNode {
  const UiList(
    super.id, {
    required this.dataset,
    required this.column,
    this.view,
    this.selected,
    super.style,
    super.semantics,
  });
  final String dataset;
  final int column;
  final UiTableView? view;

  /// The selected record ID, or null for no selection.
  final String? selected;

  @override
  Map<String, Object> props() {
    if (dataset.isEmpty) {
      throw ArgumentError.value(dataset, 'dataset', 'Must be nonempty');
    }
    if (column < 0 || column >= 64) {
      throw ArgumentError.value(column, 'column', 'Must be below 64');
    }
    if (view?.group != null) throw ArgumentError('Lists do not group');
    final selected = this.selected;
    if (selected != null &&
        (selected.isEmpty || utf8.encode(selected).length > 1024)) {
      throw ArgumentError.value(selected, 'selected', '1..1024 UTF-8 bytes');
    }
    return {
      'kind': 'list',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('list'),
      if (style != null) 'style': style!.toJson(),
      'dataset': dataset,
      'column': column,
      if (view != null) 'view': view!.toJson(),
      'selected': ?selected,
    };
  }
}

/// A button that opens a native popup menu of [UiMenuEntry] items, the same
/// entries application menus take. Choosing an action entry emits its global
/// action on the event channel, like a menu bar item.
final class UiMenuButton extends UiNode {
  UiMenuButton(
    super.id,
    this.label, {
    required List<UiMenuEntry> items,
    super.style,
    super.semantics,
  }) : items = List.unmodifiable(items);
  final String label;
  final List<UiMenuEntry> items;

  @override
  Map<String, Object> props() {
    if (label.isEmpty || utf8.encode(label).length > 1024) {
      throw ArgumentError.value(label, 'label', '1..1024 UTF-8 bytes');
    }
    validateMenuEntries(items);
    return {
      'kind': 'menu_button',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('menu_button'),
      if (style != null) 'style': style!.toJson(),
      'label': label,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

/// A retained draw list painted natively inside the node's bounds. Give the
/// node a size through its style. Coordinates are logical pixels from the top
/// left; at most 4,096 commands.
final class UiCanvas extends UiNode {
  UiCanvas(super.id, List<UiDraw> commands, {super.style, super.semantics})
    : commands = List.unmodifiable(commands);
  final List<UiDraw> commands;

  @override
  Map<String, Object> props() {
    if (commands.length > 4096) {
      throw ArgumentError('A canvas allows at most 4096 commands');
    }
    return {
      'kind': 'canvas',
      'id': id,
      if (semantics != null) 'semantics': semantics!.toJson('canvas'),
      if (style != null) 'style': style!.toJson(),
      'commands': commands.map((command) => command.toJson()).toList(),
    };
  }
}

/// One canvas command. Coordinates within 8,192 px; stroke widths 0–512.
sealed class UiDraw {
  const UiDraw();
  Map<String, Object> toJson();
}

double _coordinate(double value, String name) {
  if (!value.isFinite || value.abs() > 8192) {
    throw ArgumentError.value(value, name, 'Within 8192 px');
  }
  return value;
}

double _extent(double value, double max, String name) {
  if (!value.isFinite || value < 0 || value > max) {
    throw ArgumentError.value(value, name, '0 to $max');
  }
  return value;
}

final class UiRect extends UiDraw {
  const UiRect(
    this.x,
    this.y,
    this.width,
    this.height, {
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
    this.radius = 0,
  });
  final double x;
  final double y;
  final double width;
  final double height;
  final UiColor? fill;
  final UiColor? stroke;
  final double strokeWidth;
  final double radius;

  @override
  Map<String, Object> toJson() => {
    'op': 'rect',
    'x': _coordinate(x, 'x'),
    'y': _coordinate(y, 'y'),
    'width': _extent(width, 8192, 'width'),
    'height': _extent(height, 8192, 'height'),
    if (fill != null) 'fill': fill!.toJson(),
    if (stroke != null) 'stroke': stroke!.toJson(),
    if (strokeWidth != 1)
      'stroke_width': _extent(strokeWidth, 512, 'strokeWidth'),
    if (radius != 0) 'radius': _extent(radius, 8192, 'radius'),
  };
}

final class UiCircle extends UiDraw {
  const UiCircle(
    this.cx,
    this.cy,
    this.radius, {
    this.fill,
    this.stroke,
    this.strokeWidth = 1,
  });
  final double cx;
  final double cy;
  final double radius;
  final UiColor? fill;
  final UiColor? stroke;
  final double strokeWidth;

  @override
  Map<String, Object> toJson() => {
    'op': 'circle',
    'cx': _coordinate(cx, 'cx'),
    'cy': _coordinate(cy, 'cy'),
    'radius': _extent(radius, 8192, 'radius'),
    if (fill != null) 'fill': fill!.toJson(),
    if (stroke != null) 'stroke': stroke!.toJson(),
    if (strokeWidth != 1)
      'stroke_width': _extent(strokeWidth, 512, 'strokeWidth'),
  };
}

final class UiLine extends UiDraw {
  const UiLine(
    this.x1,
    this.y1,
    this.x2,
    this.y2,
    this.color, {
    this.width = 1,
  });
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final UiColor color;
  final double width;

  @override
  Map<String, Object> toJson() => {
    'op': 'line',
    'x1': _coordinate(x1, 'x1'),
    'y1': _coordinate(y1, 'y1'),
    'x2': _coordinate(x2, 'x2'),
    'y2': _coordinate(y2, 'y2'),
    'color': color.toJson(),
    if (width != 1) 'width': _extent(width, 512, 'width'),
  };
}

/// A stroked or filled polyline through 2 to 4,096 points.
final class UiPolyline extends UiDraw {
  UiPolyline(
    List<(double, double)> points, {
    this.stroke,
    this.width = 1,
    this.fill,
    this.close = false,
  }) : points = List.unmodifiable(points);
  final List<(double, double)> points;
  final UiColor? stroke;
  final double width;
  final UiColor? fill;
  final bool close;

  @override
  Map<String, Object> toJson() {
    if (points.length < 2 || points.length > 4096) {
      throw ArgumentError('A polyline needs 2 to 4096 points');
    }
    if (stroke == null && fill == null) {
      throw ArgumentError('A polyline needs a stroke or a fill');
    }
    return {
      'op': 'polyline',
      'points': [
        for (final (x, y) in points) [_coordinate(x, 'x'), _coordinate(y, 'y')],
      ],
      if (stroke != null) 'stroke': stroke!.toJson(),
      if (width != 1) 'width': _extent(width, 512, 'width'),
      if (fill != null) 'fill': fill!.toJson(),
      if (close) 'close': true,
    };
  }
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
  Map<String, Object> props() {
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
  Map<String, Object> props() {
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
  Map<String, Object> props() {
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
  Map<String, Object> props() {
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
  Map<String, Object> props() => {
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
  Map<String, Object> props() => {
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
  Map<String, Object> props() {
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

/// A controlled radio group. Arrows/Home/End move focus and request selection.
/// Space selects the focused option. Publish radio_change event.selected to accept.
final class UiRadioGroup extends UiNode {
  UiRadioGroup(
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
  Map<String, Object> props() {
    _validateChoices(options, selected);
    return {
      'kind': 'radio_group',
      'id': id,
      'options': options.map((o) => o.toJson()).toList(),
      'selected': selected,
      'disabled': disabled,
      if (style != null) 'style': style!.toJson(),
      if (semantics != null) 'semantics': semantics!.toJson('radio_group'),
    };
  }
}

List<Map<String, Object>> _encodeContextMenu(List<UiMenuEntry> entries) {
  validateMenuEntries(entries);
  return entries.map((entry) => entry.toJson()).toList();
}
