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

/// Rows are copied to Rust. GPUI materializes only the visible table cells.
final class UiTable extends UiNode {
  UiTable(
    super.id, {
    required List<String> columns,
    required List<List<String>> rows,
  }) : columns = List.unmodifiable(columns),
       rows = List.unmodifiable(
         rows.map((row) => List<String>.unmodifiable(row)),
       );
  final List<String> columns;
  final List<List<String>> rows;
  @override
  Map<String, Object> toJson() => {
    'kind': 'table',
    'id': id,
    'data': {'columns': columns, 'rows': rows},
  };
}
