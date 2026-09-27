import 'dart:convert';
import 'dart:math';

import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/src/tree_diff.dart';
import 'package:test/test.dart';

/// Applies operations with the native host's semantics to a JSON tree, so a
/// diff is correct only when the replayed tree equals the target description.
Map<String, Object> applyOps(
  Map<String, Object> root,
  List<Map<String, Object?>> ops,
) {
  final tree = jsonDecode(jsonEncode(root)) as Map<String, dynamic>;
  Map<String, dynamic>? find(Map<String, dynamic> node, String id) {
    if (node['id'] == id) return node;
    for (final child in (node['children'] as List?) ?? const []) {
      final found = find(child as Map<String, dynamic>, id);
      if (found != null) return found;
    }
    return null;
  }

  Map<String, dynamic>? detach(Map<String, dynamic> node, String id) {
    final children = node['children'] as List?;
    if (children == null) return null;
    final index = children.indexWhere((child) => child['id'] == id);
    if (index != -1) return children.removeAt(index) as Map<String, dynamic>;
    for (final child in children) {
      final found = detach(child as Map<String, dynamic>, id);
      if (found != null) return found;
    }
    return null;
  }

  Set<String> ids(Map<String, dynamic> node) => {
    node['id'] as String,
    for (final child in (node['children'] as List?) ?? const [])
      ...ids(child as Map<String, dynamic>),
  };

  for (final op in ops) {
    switch (op['op']) {
      case 'insert':
        final parent = find(tree, op['parent'] as String)!;
        final node = jsonDecode(jsonEncode(op['node'])) as Map<String, dynamic>;
        final existing = ids(tree);
        expect(ids(node).intersection(existing), isEmpty, reason: 'insert $op');
        (parent['children'] as List).add(node);
      case 'reparent':
        final node = detach(tree, op['id'] as String);
        expect(node, isNotNull, reason: 'reparent $op');
        final parent = find(tree, op['parent'] as String)!;
        (parent['children'] as List).add(node);
      case 'remove':
        expect(
          detach(tree, op['id'] as String),
          isNotNull,
          reason: 'remove $op',
        );
      case 'set':
        final node = find(tree, op['id'] as String)!;
        final fields = op['node'] as Map<String, Object>;
        expect(fields['kind'], node['kind'], reason: 'set $op');
        final children = node['children'];
        node
          ..clear()
          ..addAll(fields);
        if (children != null) node['children'] = children;
      case 'children':
        final node = find(tree, op['id'] as String)!;
        final current = node['children'] as List;
        final order = (op['children'] as List).cast<String>();
        expect(
          current.map((child) => child['id']).toSet(),
          order.toSet(),
          reason: 'children $op',
        );
        expect(order.length, current.length, reason: 'children $op');
        final byId = {for (final child in current) child['id']: child};
        node['children'] = [for (final id in order) byId[id]];
      default:
        fail('Unknown op $op');
    }
  }
  return (jsonDecode(jsonEncode(tree)) as Map).cast<String, Object>();
}

String canonical(Object? value) {
  Object? sort(Object? value) => switch (value) {
    Map map => {
      for (final key in map.keys.map((k) => k as String).toList()..sort())
        key: sort(map[key]),
    },
    List list => list.map(sort).toList(),
    _ => value,
  };
  return jsonEncode(sort(value));
}

List<Map<String, Object?>> diff(UiNode before, UiNode after) => diffDescribed(
  DescribedNode.describe(before),
  DescribedNode.describe(after),
)!;

void expectRoundTrip(UiNode before, UiNode after, {Object? ops}) {
  final operations = diff(before, after);
  if (ops != null) expect(operations, ops);
  expect(
    canonical(applyOps(before.toJson(), operations)),
    canonical(after.toJson()),
    reason: 'ops: $operations',
  );
}

void main() {
  test('an unchanged tree produces no operations', () {
    final tree = UiColumn('root', [
      const UiText('a', 'A'),
      UiRow('row', [const UiButton('b', 'B')]),
    ]);
    expectRoundTrip(tree, tree, ops: isEmpty);
  });

  test('a property change is one set with the fields and no children', () {
    final before = UiColumn('root', [const UiText('a', 'A')]);
    final after = UiColumn('root', [const UiText('a', 'B')]);
    expectRoundTrip(
      before,
      after,
      ops: [
        {
          'op': 'set',
          'id': 'a',
          'node': {'kind': 'text', 'id': 'a', 'text': 'B'},
        },
      ],
    );
    final styled = UiColumn('root', [
      const UiText('a', 'A'),
    ], style: const UiStyle(gap: 4));
    expectRoundTrip(
      before,
      styled,
      ops: [
        {
          'op': 'set',
          'id': 'root',
          'node': {
            'kind': 'column',
            'id': 'root',
            'style': {'gap': 4},
          },
        },
      ],
    );
  });

  test('nested values compare deeply', () {
    final before = UiColumn('root', [
      UiSelect(
        'select',
        options: const [UiSelectOption('x', 'X'), UiSelectOption('y', 'Y')],
        selected: 'x',
      ),
    ]);
    final same = UiColumn('root', [
      UiSelect(
        'select',
        options: const [UiSelectOption('x', 'X'), UiSelectOption('y', 'Y')],
        selected: 'x',
      ),
    ]);
    final relabeled = UiColumn('root', [
      UiSelect(
        'select',
        options: const [UiSelectOption('x', 'X'), UiSelectOption('y', 'Why')],
        selected: 'x',
      ),
    ]);
    expectRoundTrip(before, same, ops: isEmpty);
    expectRoundTrip(before, relabeled, ops: hasLength(1));
  });

  test('append, remove and reorder children', () {
    final before = UiColumn('root', [
      const UiText('a', 'A'),
      const UiText('b', 'B'),
      const UiText('c', 'C'),
    ]);
    expectRoundTrip(
      before,
      UiColumn('root', [
        const UiText('a', 'A'),
        const UiText('b', 'B'),
        const UiText('c', 'C'),
        const UiText('d', 'D'),
      ]),
      ops: [
        {
          'op': 'insert',
          'parent': 'root',
          'node': {'kind': 'text', 'id': 'd', 'text': 'D'},
        },
      ],
    );
    expectRoundTrip(
      before,
      UiColumn('root', [const UiText('a', 'A'), const UiText('c', 'C')]),
      ops: [
        {'op': 'remove', 'id': 'b'},
      ],
    );
    expectRoundTrip(
      before,
      UiColumn('root', [
        const UiText('c', 'C'),
        const UiText('a', 'A'),
        const UiText('b', 'B'),
      ]),
      ops: [
        {
          'op': 'children',
          'id': 'root',
          'children': ['c', 'a', 'b'],
        },
      ],
    );
    expectRoundTrip(
      before,
      UiColumn('root', [
        const UiText('d', 'D'),
        const UiText('a', 'A'),
        const UiText('c', 'C'),
      ]),
    );
  });

  test('a retained node moves into a new container and back out', () {
    final before = UiColumn('root', [
      const UiInput('name', placeholder: 'Name'),
      const UiText('a', 'A'),
    ]);
    final wrapped = UiColumn('root', [
      UiRow('row', [
        const UiText('label', 'Name'),
        const UiInput('name', placeholder: 'Name'),
      ]),
      const UiText('a', 'A'),
    ]);
    final ops = diff(before, wrapped);
    expect(ops.map((op) => op['op']), ['insert', 'reparent', 'children']);
    expect((ops[0]['node'] as Map)['children'], [
      {'kind': 'text', 'id': 'label', 'text': 'Name'},
    ]);
    expectRoundTrip(before, wrapped);
    expectRoundTrip(wrapped, before);
  });

  test('stack and scroll containers diff like rows and columns', () {
    final before = UiColumn('root', [
      UiScroll('list', [const UiText('a', 'A'), const UiText('b', 'B')]),
      UiStack('layers', [const UiText('under', 'U')]),
    ]);
    final after = UiColumn('root', [
      UiScroll('list', [
        const UiText('b', 'B'),
        const UiText('a', 'A'),
      ], axis: UiScrollAxis.both),
      UiStack('layers', [
        const UiText('under', 'U'),
        const UiText('badge', 'Badge', style: UiStyle(inset: UiInset(top: 2))),
      ]),
    ]);
    final ops = diff(before, after);
    expect(ops.map((op) => op['op']), ['insert', 'set', 'children']);
    expect((ops[1]['node'] as Map).containsKey('children'), isFalse);
    expectRoundTrip(before, after);
  });

  test('a survivor leaves a removed subtree before the removal', () {
    final before = UiColumn('root', [
      UiRow('row', [
        const UiText('gone', 'Gone'),
        const UiInput('keep', placeholder: 'Keep'),
      ]),
    ]);
    final after = UiColumn('root', [
      const UiInput('keep', placeholder: 'Kept'),
    ]);
    final ops = diff(before, after);
    expect(ops.map((op) => op['op']), ['reparent', 'remove', 'set']);
    expectRoundTrip(before, after);
  });

  test('identity and kind changes fall back to a whole description', () {
    final before = UiColumn('root', [const UiText('a', 'A')]);
    expect(
      diffDescribed(
        DescribedNode.describe(before),
        DescribedNode.describe(UiColumn('other', [const UiText('a', 'A')])),
      ),
      isNull,
    );
    expect(
      diffDescribed(
        DescribedNode.describe(before),
        DescribedNode.describe(UiRow('root', [const UiText('a', 'A')])),
      ),
      isNull,
    );
    expect(
      diffDescribed(
        DescribedNode.describe(before),
        DescribedNode.describe(UiColumn('root', [const UiButton('a', 'A')])),
      ),
      isNull,
    );
  });

  test('random edits replay to the target tree', () {
    final random = Random(20260927);
    var serial = 0;
    UiNode leaf(String id) => switch (random.nextInt(3)) {
      0 => UiText(id, 'T${random.nextInt(3)}'),
      1 => UiButton(id, 'B${random.nextInt(3)}'),
      _ => UiInput(id, placeholder: 'P${random.nextInt(3)}'),
    };
    UiNode build(int depth, List<String> pool) {
      final id = pool.removeLast();
      if (depth == 0 || random.nextInt(3) == 0) return leaf(id);
      final count = random.nextInt(4);
      final children = [
        for (var i = 0; i < count && pool.isNotEmpty; i++)
          build(depth - 1, pool),
      ];
      return random.nextBool() ? UiColumn(id, children) : UiRow(id, children);
    }

    for (var round = 0; round < 300; round++) {
      final pool = [for (var i = 0; i < 14; i++) 'n$i']..shuffle(random);
      final before = build(3, [...pool, 'root']);
      // Keep the root identity and kind; everything below may change.
      final beforeRoot = before is UiColumn
          ? before
          : UiColumn('root', before.children);
      final afterPool = [for (var i = 0; i < 14; i++) 'n$i']
        ..shuffle(random)
        ..add('x${serial++}');
      final rebuilt = build(3, [...afterPool, 'root']);
      final afterRoot = UiColumn('root', rebuilt.children);
      final ops = diffDescribed(
        DescribedNode.describe(beforeRoot),
        DescribedNode.describe(afterRoot),
      );
      if (ops == null) continue;
      expect(
        canonical(applyOps(beforeRoot.toJson(), ops)),
        canonical(afterRoot.toJson()),
        reason: 'round $round ops $ops',
      );
    }
  });
}
