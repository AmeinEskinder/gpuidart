import 'nodes.dart';

/// A described node: its complete JSON plus the same children as typed nodes.
/// `json['children']` holds the children's own `json` maps, so the full
/// description is available without a second serialization pass.
///
/// A description remembers the [UiNode] it came from. Describing the next
/// tree against the previous description reuses every subtree whose node
/// instance is unchanged, so a rebuild that keeps unchanged parts as the
/// same objects (const nodes, [UiMemo]) costs the changed parts, and so does
/// the diff that follows.
final class DescribedNode {
  DescribedNode._(this.json, this.source, this._parent);

  /// Describes [node]. With [previous], the description published before,
  /// unchanged subtrees are reused; call [seal] once the diff against
  /// [previous] has run.
  factory DescribedNode.describe(UiNode node, {DescribedNode? previous}) {
    final reused = <(DescribedNode, DescribedNode?)>[];
    final root = _describe(node, previous, null, reused);
    root._reused = reused;
    return root;
  }

  static DescribedNode _describe(
    UiNode node,
    DescribedNode? previous,
    DescribedNode? parent,
    List<(DescribedNode, DescribedNode?)> reused,
  ) {
    if (previous != null && identical(previous.source, node)) {
      previous._pendingParent = parent;
      previous._hasPendingParent = true;
      reused.add((previous, parent));
      return previous;
    }
    final json = node.props();
    final described = DescribedNode._(json, node, parent);
    if (node.isContainer) {
      final children = node.children;
      final previousChildren = previous?.children;
      final childJson = <Object>[];
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        var candidate =
            previousChildren != null &&
                i < previousChildren.length &&
                previousChildren[i].id == child.id
            ? previousChildren[i]
            : null;
        candidate ??= previous?._childById(child.id);
        final describedChild = _describe(child, candidate, described, reused);
        described.children.add(describedChild);
        childJson.add(describedChild.json);
      }
      json['children'] = childJson;
    }
    return described;
  }

  DescribedNode? _childById(String id) {
    for (final child in children) {
      if (child.id == id) return child;
    }
    return null;
  }

  /// Moves reused subtrees under their new parents. Until then their parent
  /// links describe the previous tree, which the diff relies on.
  void seal() {
    final reused = _reused;
    if (reused == null) return;
    for (final (node, parent) in reused) {
      node._parent = parent;
      node._hasPendingParent = false;
      node._pendingParent = null;
    }
    _reused = null;
  }

  final Map<String, Object> json;

  /// The typed node this description came from.
  final UiNode source;
  final List<DescribedNode> children = [];
  DescribedNode? _parent;
  DescribedNode? _pendingParent;
  bool _hasPendingParent = false;
  List<(DescribedNode, DescribedNode?)>? _reused;
  String get id => json['id'] as String;
  String get kind => json['kind'] as String;
  bool get isContainer => json.containsKey('children');

  /// The parent in the tree being described: the pending one for a reused
  /// subtree root, the recorded one otherwise.
  DescribedNode? get _currentParent =>
      _hasPendingParent ? _pendingParent : _parent;

  // Scratch for one diff, valid while `_mark` equals the diff's epoch. On
  // the old tree: whether the new tree keeps this node and under which new
  // node. On the new tree: the old node it keeps.
  int _mark = 0;
  bool _retainedValue = false;
  DescribedNode? _newParentValue;
  DescribedNode? _beforeValue;

  Map<String, DescribedNode>? _byId;

  /// The node with [id] in this tree; the index is built on first use and
  /// stays valid because publications never restructure a description in
  /// place, only [replaceOwnFields] changes one.
  DescribedNode? find(String id) {
    var index = _byId;
    if (index == null) {
      index = <String, DescribedNode>{};
      void collect(DescribedNode node) {
        index![node.id] = node;
        node.children.forEach(collect);
      }

      collect(this);
      _byId = index;
    }
    return index[id];
  }

  /// Replaces this node's own fields with [fields], keeping its children.
  void replaceOwnFields(Map<String, Object> fields) {
    final children = json['children'];
    json
      ..clear()
      ..addAll(fields);
    if (children != null) json['children'] = children;
  }

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
/// publications send the whole description instead. Subtrees reused from
/// [old] are skipped whole.
List<Map<String, Object?>>? diffDescribed(
  DescribedNode old,
  DescribedNode next,
) {
  if (identical(old, next)) return const [];
  if (old.id != next.id || old.kind != next.kind) return null;
  final matcher = _Matcher(old);
  if (!matcher.match(next, old)) return null;
  final epoch = matcher.epoch;

  final inserts = <Map<String, Object?>>[];
  final reparents = <Map<String, Object?>>[];
  final removes = <Map<String, Object?>>[];
  final sets = <Map<String, Object?>>[];
  final orders = <Map<String, Object?>>[];

  DescribedNode? before(DescribedNode node) =>
      node._mark == epoch ? node._beforeValue : null;
  bool retained(DescribedNode node) =>
      node._mark == epoch && node._retainedValue;
  DescribedNode? newParent(DescribedNode node) =>
      node._mark == epoch ? node._newParentValue : null;

  // The insert payload for a new node keeps only new descendants. Retained
  // descendants are reparented under it after the insert.
  Map<String, Object> payload(DescribedNode node) => {
    ...node.ownFields(),
    if (node.isContainer)
      'children': [
        for (final child in node.children)
          if (before(child) == null) payload(child),
      ],
  };

  void visit(DescribedNode node) {
    final previous = before(node);
    // A reused subtree is the previous subtree: nothing changed below it.
    if (identical(previous, node)) return;
    if (previous != null && !previous.sameOwnFields(node)) {
      sets.add({'op': 'set', 'id': node.id, 'node': node.ownFields()});
    }
    if (node.children.isEmpty &&
        (previous == null || previous.children.isEmpty)) {
      return;
    }
    // Membership once inserts, reparents and removes have run: children that
    // stay under this node keep their order, inserted ones append, reparented
    // ones append after every insert.
    final surviving = <String>[
      if (previous != null)
        for (final child in previous.children)
          if (retained(child) && identical(newParent(child), node)) child.id,
    ];
    final inserted = <String>[];
    final reparented = <String>[];
    for (final child in node.children) {
      final childBefore = before(child);
      if (childBefore == null) {
        if (previous != null) {
          inserts.add({
            'op': 'insert',
            'parent': node.id,
            'node': payload(child),
          });
        }
        inserted.add(child.id);
      } else if (previous == null ||
          !identical(childBefore._parent, previous)) {
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
      if (identical(before(child), child)) continue;
      if (retained(child)) {
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
/// the index over the old tree is built on the first miss. Scratch state is
/// stamped with a fresh epoch, so nothing is reset between diffs.
final class _Matcher {
  _Matcher(this.old) : epoch = ++_epochs;

  static int _epochs = 0;
  final int epoch;
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

  void stamp(DescribedNode node) {
    if (node._mark != epoch) {
      node._mark = epoch;
      node._retainedValue = false;
      node._newParentValue = null;
      node._beforeValue = null;
    }
  }

  /// Returns false when a node keeps its ID but changes kind.
  bool match(DescribedNode node, DescribedNode? before) {
    stamp(node);
    node._beforeValue = before;
    if (before != null) {
      if (before.kind != node.kind) return false;
      stamp(before);
      before._retainedValue = true;
      before._newParentValue = node._currentParent;
      // The same instance on both sides: its subtree is unchanged.
      if (identical(node, before)) return true;
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
