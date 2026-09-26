import 'dart:convert';

/// Full Dart tree walk, with sibling identity based on explicit IDs. Styles and
/// kinds are constant in the measured fixture; unsupported changes fail loudly.
({List<Map<String, Object?>> ops, int visited}) diffDescriptions(
  Map old,
  Map next,
) {
  final ops = <Map<String, Object?>>[];
  var visited = 0;
  void walk(Map before, Map after) {
    visited++;
    if (before['id'] != after['id'] ||
        before['kind'] != after['kind'] ||
        jsonEncode(before['style']) != jsonEncode(after['style'])) {
      throw StateError(
        'Experimental diff only supports fixed-kind/style identities',
      );
    }
    if (after['kind'] == 'text' && before['text'] != after['text']) {
      ops.add({'op': 'text', 'id': after['id'], 'text': after['text']});
    }
    final previous = (before['children'] as List?)?.cast<Map>();
    final current = (after['children'] as List?)?.cast<Map>();
    if (previous == null || current == null) return;
    final oldById = {for (final node in previous) node['id']: node};
    final nextIds = current.map((node) => node['id']).toSet();
    final working = previous.map((node) => node['id']).toList();
    for (final node in previous) {
      if (!nextIds.contains(node['id'])) {
        ops.add({'op': 'remove', 'id': node['id']});
        working.remove(node['id']);
      }
    }
    for (var index = 0; index < current.length; index++) {
      final node = current[index];
      final id = node['id'];
      final from = working.indexOf(id);
      if (from == -1) {
        ops.add({
          'op': 'insert',
          'parent': after['id'],
          'index': index,
          'node': node,
        });
        working.insert(index, id);
      } else {
        if (from != index) {
          ops.add({
            'op': 'move',
            'parent': after['id'],
            'id': id,
            'index': index,
          });
          working.removeAt(from);
          working.insert(index, id);
        }
        walk(oldById[id]!, node);
      }
    }
  }

  walk(old, next);
  return (ops: ops, visited: visited);
}
