import 'dart:convert';
import 'dart:typed_data';

import 'style.dart';
import 'table_view.dart';

sealed class UiNode {
  const UiNode(this.id, {this.style});
  final String id;
  final UiStyle? style;
  Map<String, Object> toJson();
}

final class UiColumn extends UiNode {
  UiColumn(super.id, List<UiNode> children, {super.style})
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'column',
    'id': id,
    if (style != null) 'style': style!.toJson(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// A horizontal group that wraps to another line when the window is narrow.
final class UiRow extends UiNode {
  UiRow(super.id, List<UiNode> children, {super.style})
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'row',
    'id': id,
    if (style != null) 'style': style!.toJson(),
    'children': children.map((child) => child.toJson()).toList(),
  };
}

final class UiText extends UiNode {
  const UiText(super.id, this.text, {super.style});
  final String text;
  @override
  Map<String, Object> toJson() => {
    'kind': 'text',
    'id': id,
    if (style != null) 'style': style!.toJson(),
    'text': text,
  };
}

final class UiButton extends UiNode {
  const UiButton(super.id, this.label, {super.style});
  final String label;
  @override
  Map<String, Object> toJson() => {
    'kind': 'button',
    'id': id,
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
      if (style != null) 'style': style!.toJson(),
      'min': min,
      'max': max,
      'step': step,
      'number': number,
      'disabled': disabled,
    };
  }
}

/// Native text, cursor, selection and undo state survive snapshots with this ID.
final class UiInput extends UiNode {
  const UiInput(super.id, {super.style, this.placeholder = ''});
  final String placeholder;
  @override
  Map<String, Object> toJson() => {
    'kind': 'input',
    'id': id,
    if (style != null) 'style': style!.toJson(),
    'placeholder': placeholder,
  };
}

/// References a dataset registered with this host. Snapshots contain no records.
final class UiTable extends UiNode {
  const UiTable(super.id, {super.style, required this.dataset, this.view});
  final String dataset;

  /// Presentation-only sort/filter view over the dataset.
  final UiTableView? view;
  @override
  Map<String, Object> toJson() => {
    'kind': 'table',
    'id': id,
    if (style != null) 'style': style!.toJson(),
    'dataset': dataset,
    if (view != null) 'view': view!.toJson(),
  };
}
