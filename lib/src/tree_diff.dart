import 'nodes.dart';

/// A described node: its complete JSON plus the same children as typed nodes.
/// `json['children']` holds the children's own `json` maps, so the full
/// description is available without a second serialization pass.
final class DescribedNode {
  DescribedNode._(this.json, this.children);

  factory DescribedNode.describe(UiNode node) =>
      DescribedNode._wrap(node.toJson());

  static DescribedNode _wrap(Map<String, Object> json) =>
      DescribedNode._(json, [
        for (final child
            in (json['children'] as List<Object>?) ?? const <Object>[])
          _wrap(child as Map<String, Object>),
      ]);

  final Map<String, Object> json;
  final List<DescribedNode> children;
  String get id => json['id'] as String;
  String get kind => json['kind'] as String;
  bool get isContainer => kind == 'column' || kind == 'row';

  /// Every node ID in this subtree.
  Set<String> ids() => {id, for (final child in children) ...child.ids()};

  /// Own fields only, the payload of a `set` operation.
  Map<String, Object> ownFields() => {
    for (final entry in json.entries)
      if (entry.key != 'children') entry.key: entry.value,
  };

  bool sameOwnFields(DescribedNode other) {
    if (json.length != other.json.length) return false;
    for (final entry in json.entries) {
      if (entry.key == 'children') continue;
      if (!other.json.containsKey(entry.key) ||
          !_deepEquals(entry.value, other.json[entry.key])) {
        return false;
      }
    }
    return true;
  }
}

/// Operations that turn the previous tree into the next one. Apply order is
/// inserts, reparents, removes, sets, then child orders, so every operation
/// finds its targets and no index arithmetic is needed. Returns null when the
/// root changes identity or any node changes kind under the same ID; those
/// publications send the whole description instead.
List<Map<String, Object?>>? diffDescribed(
  DescribedNode old,
  DescribedNode next,
) {
  if (old.id != next.id || old.kind != next.kind) return null;
  final oldById = <String, DescribedNode>{};
  final oldParent = <String, String>{};
  void indexOld(DescribedNode node) {
    oldById[node.id] = node;
    for (final child in node.children) {
      oldParent[child.id] = node.id;
      indexOld(child);
    }
  }

  indexOld(old);
  final newById = <String, DescribedNode>{};
  void indexNew(DescribedNode node) {
    newById[node.id] = node;
    node.children.forEach(indexNew);
  }

  indexNew(next);
  for (final entry in newById.entries) {
    final before = oldById[entry.key];
    if (before != null && before.kind != entry.value.kind) return null;
  }

  final inserts = <Map<String, Object?>>[];
  final reparents = <Map<String, Object?>>[];
  final removes = <Map<String, Object?>>[];
  final sets = <Map<String, Object?>>[];
  final orders = <Map<String, Object?>>[];

  // The insert payload for a new node keeps only new descendants. Retained
  // descendants are reparented under it after the insert.
  Map<String, Object> payload(DescribedNode node) => {
    ...node.ownFields(),
    if (node.isContainer)
      'children': [
        for (final child in node.children)
          if (!oldById.containsKey(child.id)) payload(child),
      ],
  };

  void visit(DescribedNode node, DescribedNode? before) {
    if (before != null && !before.sameOwnFields(node)) {
      sets.add({'op': 'set', 'id': node.id, 'node': node.ownFields()});
    }
    // Membership once inserts, reparents and removes have run: surviving
    // children keep their order, inserted ones append, reparented ones append
    // after every insert.
    final surviving = <String>[
      if (before != null)
        for (final child in before.children)
          if (newById.containsKey(child.id) && oldParent[child.id] == node.id)
            child.id,
    ];
    final inserted = <String>[];
    final reparented = <String>[];
    for (final child in node.children) {
      final childBefore = oldById[child.id];
      if (childBefore == null) {
        if (before != null) {
          inserts.add({
            'op': 'insert',
            'parent': node.id,
            'node': payload(child),
          });
        }
        inserted.add(child.id);
        visit(child, null);
      } else {
        if (before == null || oldParent[child.id] != node.id) {
          reparents.add({'op': 'reparent', 'id': child.id, 'parent': node.id});
          reparented.add(child.id);
        }
        visit(child, childBefore);
      }
    }
    final resulting = [...surviving, ...inserted, ...reparented];
    final desired = [for (final child in node.children) child.id];
    if (!_sameIds(resulting, desired)) {
      orders.add({'op': 'children', 'id': node.id, 'children': desired});
    }
  }

  visit(next, old);

  void collectRemoved(DescribedNode node) {
    for (final child in node.children) {
      if (newById.containsKey(child.id)) {
        collectRemoved(child);
      } else {
        removes.add({'op': 'remove', 'id': child.id});
      }
    }
  }

  collectRemoved(old);
  return [...inserts, ...reparents, ...removes, ...sets, ...orders];
}

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_deepEquals(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
