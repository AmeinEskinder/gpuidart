import 'nodes.dart';

/// A described node: its complete JSON plus the same children as typed nodes.
/// `json['children']` holds the children's own `json` maps, so the full
/// description is available without a second serialization pass.
final class DescribedNode {
  DescribedNode._(this.json, this._parent);

  factory DescribedNode.describe(UiNode node) =>
      DescribedNode._wrap(node.toJson(), null);

  static DescribedNode _wrap(Map<String, Object> json, DescribedNode? parent) {
    final node = DescribedNode._(json, parent);
    final children = json['children'] as List<Object>?;
    if (children != null) {
      for (final child in children) {
        node.children.add(_wrap(child as Map<String, Object>, node));
      }
    }
    return node;
  }

  final Map<String, Object> json;
  final List<DescribedNode> children = [];
  final DescribedNode? _parent;
  String get id => json['id'] as String;
  String get kind => json['kind'] as String;
  bool get isContainer => json.containsKey('children');

  // Scratch for one diff. On the old tree: whether the new tree keeps this
  // node and under which new node. On the new tree: the old node it keeps.
  bool _retained = false;
  DescribedNode? _newParent;
  DescribedNode? _before;

  /// Every node ID in this subtree.
  Set<String> ids() {
    final all = <String>{};
    void collect(DescribedNode node) {
      all.add(node.id);
      node.children.forEach(collect);
    }

    collect(this);
    return all;
  }

  /// Own fields only, the payload of a `set` operation.
  Map<String, Object> ownFields() => {
    for (final entry in json.entries)
      if (entry.key != 'children') entry.key: entry.value,
  };

  bool sameOwnFields(DescribedNode other) {
    final theirs = other.json;
    if (json.length != theirs.length) return false;
    for (final entry in json.entries) {
      if (entry.key == 'children') continue;
      final value = entry.value;
      final counterpart = theirs[entry.key];
      if (counterpart == null) return false;
      if (value is String || value is num || value is bool) {
        if (value != counterpart) return false;
      } else if (!_deepEquals(value, counterpart)) {
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
  if (!_Matcher(old).match(next, old)) return null;

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
          if (child._before == null) payload(child),
      ],
  };

  void visit(DescribedNode node) {
    final before = node._before;
    if (before != null && !before.sameOwnFields(node)) {
      sets.add({'op': 'set', 'id': node.id, 'node': node.ownFields()});
    }
    if (node.children.isEmpty && (before == null || before.children.isEmpty)) {
      return;
    }
    // Membership once inserts, reparents and removes have run: children that
    // stay under this node keep their order, inserted ones append, reparented
    // ones append after every insert.
    final surviving = <String>[
      if (before != null)
        for (final child in before.children)
          if (child._retained && identical(child._newParent, node)) child.id,
    ];
    final inserted = <String>[];
    final reparented = <String>[];
    for (final child in node.children) {
      final childBefore = child._before;
      if (childBefore == null) {
        if (before != null) {
          inserts.add({
            'op': 'insert',
            'parent': node.id,
            'node': payload(child),
          });
        }
        inserted.add(child.id);
      } else if (before == null || !identical(childBefore._parent, before)) {
        reparents.add({'op': 'reparent', 'id': child.id, 'parent': node.id});
        reparented.add(child.id);
      }
      visit(child);
    }
    final resulting = [...surviving, ...inserted, ...reparented];
    final desired = [for (final child in node.children) child.id];
    if (!_sameIds(resulting, desired)) {
      orders.add({'op': 'children', 'id': node.id, 'children': desired});
    }
  }

  visit(next);

  void collectRemoved(DescribedNode node) {
    for (final child in node.children) {
      if (child._retained) {
        collectRemoved(child);
      } else {
        removes.add({'op': 'remove', 'id': child.id});
      }
    }
  }

  collectRemoved(old);
  return [...inserts, ...reparents, ...removes, ...sets, ...orders];
}

/// Pairs every new node with the old node of the same ID. Children are tried
/// by position first, so a tree that keeps its order never touches the index;
/// the index over the old tree is built on the first miss.
final class _Matcher {
  _Matcher(this.old) {
    void reset(DescribedNode node) {
      node._retained = false;
      node._newParent = null;
      node.children.forEach(reset);
    }

    reset(old);
  }

  final DescribedNode old;
  Map<String, DescribedNode>? _oldById;

  Map<String, DescribedNode> get oldById {
    final index = _oldById;
    if (index != null) return index;
    final built = <String, DescribedNode>{};
    void collect(DescribedNode node) {
      built[node.id] = node;
      node.children.forEach(collect);
    }

    collect(old);
    return _oldById = built;
  }

  /// Returns false when a node keeps its ID but changes kind.
  bool match(DescribedNode node, DescribedNode? before) {
    node._before = before;
    if (before != null) {
      if (before.kind != node.kind) return false;
      before._retained = true;
      before._newParent = node._parent;
    }
    final beforeChildren = before?.children;
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      var candidate = beforeChildren != null && i < beforeChildren.length
          ? beforeChildren[i]
          : null;
      if (candidate == null || candidate.id != child.id) {
        candidate = oldById[child.id];
      }
      if (!match(child, candidate)) return false;
    }
    return true;
  }
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
