sealed class UiNode {
  const UiNode(this.id);
  final String id;
  Map<String, Object> toJson();
}

final class UiColumn extends UiNode {
  UiColumn(super.id, List<UiNode> children)
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'column',
    'id': id,
    'children': children.map((child) => child.toJson()).toList(),
  };
}

/// A horizontal group that wraps to another line when the window is narrow.
final class UiRow extends UiNode {
  UiRow(super.id, List<UiNode> children)
    : children = List.unmodifiable(children);
  final List<UiNode> children;
  @override
  Map<String, Object> toJson() => {
    'kind': 'row',
    'id': id,
    'children': children.map((child) => child.toJson()).toList(),
  };
}

final class UiText extends UiNode {
  const UiText(super.id, this.text);
  final String text;
  @override
  Map<String, Object> toJson() => {'kind': 'text', 'id': id, 'text': text};
}

final class UiButton extends UiNode {
  const UiButton(super.id, this.label);
  final String label;
  @override
  Map<String, Object> toJson() => {'kind': 'button', 'id': id, 'label': label};
}

/// Native text, cursor, selection and undo state survive snapshots with this ID.
final class UiInput extends UiNode {
  const UiInput(super.id, {this.placeholder = ''});
  final String placeholder;
  @override
  Map<String, Object> toJson() => {
    'kind': 'input',
    'id': id,
    'placeholder': placeholder,
  };
}

/// References a dataset registered with this host. Snapshots contain no records.
final class UiTable extends UiNode {
  const UiTable(super.id, {required this.dataset});
  final String dataset;
  @override
  Map<String, Object> toJson() => {
    'kind': 'table',
    'id': id,
    'dataset': dataset,
  };
}
