# Retained description updates

A publication no longer has to carry the whole description. When the host can
compute the difference between the previously published tree and the new one,
it sends that difference as operations through `gd_update`, and native applies
them to the description it already holds. The public Dart API is unchanged:
`publish` and `rebuild` take a `UiNode` root, the acknowledgement is the same
`applied` event at the new revision, and hot reload still re-invokes the view
builder.

## Why

The [snapshot gate](../reports/performance/snapshot-gate/README.md) measured
one property change in a 2,048-property view at 273,772 bytes, about 4.4 ms of
Dart encoding and copying and about 3.6 ms of native decoding and validation.
That work scaled with the description, not with the change. The
[strategy comparison](../reports/performance/strategies/README.md) showed that
patches cut bytes but, in that prototype, still rebuilt, restaged and
re-rendered the whole tree. This design keeps the parts of that verdict that
hold and removes the parts that came from the prototype: native keeps the
applied tree, so a change costs a clone and a few searches instead of a full
decode, while validation and reconciliation still run over the whole result.

## Wire contract

`gd_update` accepts UTF-8 JSON with the same statuses as `gd_publish`:

```json
{
  "revision": 7,
  "base_revision": 6,
  "ops": [
    {"op": "insert", "parent": "root", "node": {"kind": "text", "id": "d", "text": "D"}},
    {"op": "reparent", "id": "name", "parent": "row"},
    {"op": "remove", "id": "c"},
    {"op": "set", "id": "a", "node": {"kind": "text", "id": "a", "text": "A2"}},
    {"op": "children", "id": "root", "children": ["d", "row", "a"]}
  ],
  "actions": []
}
```

- `base_revision` must equal the applied revision when the batch is applied.
  Otherwise the batch is rejected with `Stale base revision`.
- Operations apply in order on a copy of the applied tree. `insert` appends a
  subtree whose IDs are all new. `reparent` detaches a subtree and appends it
  to another container. `remove` detaches and drops a subtree. `set` replaces a
  node's own fields, keeps its kind and keeps its children. `children` reorders
  a container and must list each current child once.
- The result is validated exactly like a snapshot: unique IDs, depth, node
  count, per-kind bounds, action contexts, dataset references and view columns.
- Any failure rejects the whole batch with a `rejected` event and leaves the
  applied description untouched. Nothing is retained from a partial batch.
- `actions` replaces the bindings like a snapshot does; omission clears them.
- At most 4,096 operations per update; messages stay under 16 MiB.

The C header documents `gd_update` beside `gd_publish`. A native library
without the symbol still works: the Dart host looks it up lazily and publishes
whole descriptions when it is absent.

## Host behavior

`GpuiHost` keeps the described tree of the last publication that native
accepted for queueing, and its revision. `publish` describes the new root once,
diffs it against that baseline and sends the operations. It sends the whole
description instead when there is no baseline, when the root changes identity
or kind, when any node changes kind under the same ID, or when an action
binding names a context that is not in the tree, so that case still fails at
submission like it did for snapshots. After a synchronous submission failure or
an asynchronous `rejected` event the baseline is dropped, so the next
publication is a whole description again.

Queued publications pipeline: each batch is computed against the previous
queued tree, and native applies them in order. When native rejects a batch,
every batch queued behind it was computed against a tree native never held and
comes back as `Stale base revision`. Each publication carries the whole
intended tree, so on the first stale rejection the host resends the latest
queued tree as a whole description and completes every superseded publication
when that one applies. Publications keep their order, and a rejected batch
still fails with its own reason. `HostMetrics.resubmittedPublications` counts
these resends.

`HostMetrics.operationPublications` counts publications that went through
`gd_update`; `encoded_bytes` and the `dart.encode` trace stage show the size
difference directly.

The diff lives in `lib/src/tree_diff.dart`. Nodes expose their own fields
through `props()` and their children through `children`; `toJson()` composes
the two. The diff pairs every new node with the old node of the same ID,
trying children by position first so a tree that keeps its order never
touches a hash index, then walks the new tree once and emits inserts,
reparents, removes, sets and child orders in that order. It never needs index
arithmetic because native appends and the final `children` operation fixes
the order. `tool/performance/bench_diff.dart` times describe and diff alone.

## Sublinear rebuilds through identity

Describing a tree against the previous description reuses every subtree whose
`UiNode` instance is unchanged, without serializing it, and the diff skips a
reused subtree whole. A rebuild therefore costs the parts that changed when
the application hands back the same instances for the parts that did not:
`const` nodes are the same instance on every build, and `UiMemo` keeps a
built subtree while its inputs compare equal:

```dart
final header = UiMemo<UiNode>();
UiNode build() => UiColumn('root', [
  header.of([title, unread], () => UiRow('header', [...])),
  UiText('status', status),
]);
```

Reuse is positional under the same parent: a kept instance under a rebuilt
parent is found by position or ID among that parent's previous children. A
kept instance that moves to another parent is described afresh and diffs to
a reparent, as before. Nothing changes on the wire or in native.

## What does not change

- Node identity rules. The same ID and kind keeps its native entity; an ID that
  leaves the tree drops it. `reparent` keeps the entity because reconciliation
  runs over the resulting tree, not over the operations.
- Reconciliation. Inputs, tables, sliders, selects and dialogs reconcile against
  the whole resulting tree, as before.
- Revisions. Snapshot revisions still increase by one per publication and the
  `applied` event carries the new revision.

## Limits

- Native applies operations in place. It keeps an index of node IDs and
  parents beside the applied tree, so a target costs its path from the root
  rather than a walk of every node, and each operation records its inverse.
  A failing operation, binding, menu, theme or dataset check rolls the batch
  back through that log, so the applied description never shows a partial
  batch. Own fields of inserted and set nodes are validated when the update
  parses; after application native checks only identity, size, depth, the
  bindings and menus the update carries, and the datasets the touched nodes
  reference. Reconciliation of retained entities still walks the resulting
  tree.
- Rendering still materializes the whole tree every frame. Per-node entities
  with scoped invalidation are a separate change gated by the same
  measurement.
- The wire stays JSON. Whether a binary encoding earns its place is decided by
  the measured encode and decode share after this change, not before.

## Evidence

[The operation update gate](../reports/performance/update-gate/README.md)
ran the snapshot gate at trunk and head on the same machine with release
artifacts per side. At 2,048 properties a change moves 201 bytes instead of
273,772, the encode and decode stages fall from about 6 ms to under 50 us,
and publish-to-ack improves for every change kind at every size, 0.46 of
trunk for a property change at 2,048 nodes. The Dart describe plus diff and
the native clone plus revalidation are the remaining costs, which is why a
binary wire is not the next step.

`tool/performance/bench_memo.dart` times describe and diff for one field
change in a form of memoized rows, fresh rows against rows handed back by
`UiMemo`. JIT medians over 100 rounds on 2026-09-28, while a release build
ran on the same machine, so the ratios carry the claim rather than the
absolute figures:

| Fields | Describe, fresh | Describe, memoized | Diff, fresh | Diff, memoized |
| ---: | ---: | ---: | ---: | ---: |
| 128 | 192 us | 11 us | 281 us | 23 us |
| 512 | 437 us | 30 us | 539 us | 84 us |
| 2,048 | 1,688 us | 100 us | 2,099 us | 278 us |

The operations are the same 101 bytes either way. The remaining memoized
cost is the root's child list, which the diff still walks by position.
