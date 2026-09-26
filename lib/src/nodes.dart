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
