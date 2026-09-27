# Operation update gate

Trunk-versus-head run of the snapshot gate for
[retained description updates](../../../docs/retained-tree.md). Trunk is the
unmodified `dev` head the change was built on (`e5345e5`); head is `f5bc802`,
which carries operation updates plus the checkbox and structural-edit commits
that follow it and do not touch the publish path. Both sides compiled their
own AOT capture and their own release native library, so each side runs its
own SDK code end to end. `trunk/metadata.json` and `head/metadata.json` record
the source revision, a clean working tree and the native library hash for each
side.

## Method

`tool/performance/run_update_gate.ps1` builds release artifacts for each side
into a side-specific native directory, records the source revision beside
them, runs `tool/performance/run_snapshot_gate.dart` (three repetitions,
sizes 128, 512 and 2,048 rotated, JIT and AOT, 720 state-preserving
replacements in all) and summarizes each series with
`tool/performance/summarize_snapshot_gate.dart`. `comparison.md` is the output
of `tool/performance/compare_update_gate.dart` over the two summaries: medians
across runs of each run's median, and the head-over-trunk ratio. The workload
is unchanged: eight unchanged, property, reorder, insert and remove
publications per size through `rebuild`, with a retained input and a retained
table checked after every publication. All 36 runs passed on both sides.

Sides ran one after the other, trunk first, on the same machine in one
session (`environment.json`). The head build ran once more after a gate-runner
fix; the trunk series is the first run's.

## Result, AOT, 2,048 properties

| Operation | Metric | Trunk | Head | Head / trunk |
| --- | --- | ---: | ---: | ---: |
| property | Bytes | 273,772 | 201 | 0.00 |
| property | Describe, us | 399 | 589 | 1.47 |
| property | Diff, us | | 2,765 | |
| property | Encode/copy, us | 2,837 | 18 | 0.01 |
| property | Native decode/validate, us | 3,176 | 28 | 0.01 |
| property | Native dispatch, us | 541 | 1,260 | 2.33 |
| property | Publish to ack, us | 7,197 | 5,324 | 0.74 |
| reorder | Bytes | 273,772 | 941 | 0.00 |
| reorder | Publish to ack, us | 7,742 | 5,125 | 0.66 |
| insert | Bytes | 274,002 | 132 | 0.00 |
| insert | Publish to ack, us | 7,665 | 5,730 | 0.75 |
| remove | Bytes | 273,951 | 73 | 0.00 |
| remove | Publish to ack, us | 23,652 | 8,050 | 0.34 |
| unchanged | Bytes | 273,771 | 41 | 0.00 |
| unchanged | Publish to ack, us | 10,311 | 17,171 | 1.67 |

At 128 properties the publish-to-ack medians are within 5 percent of each
other for property changes (690 versus 715 us) and lower on head for insert
and remove (691 to 566 us, 611 to 476 us); the diff costs about 200 us there.
At 512 properties every change kind acknowledges faster on head (0.68 to 0.94
of trunk). JIT rows follow the same shape; see `comparison.md`.

## Reading

- The transfer and the two serialization stages are gone from the change
  path. What remains on head is the Dart describe plus diff, 3.4 ms at 2,048
  nodes, and a native dispatch that doubled because the update is applied on
  a clone of the tree and the result is validated in full.
- The Dart diff is now the largest stage. It costs about 1.3 us per node,
  which is hash-map work: two indexes over the trees, a parent map and
  several lookups per node. That is the next target; a binary wire would
  save at most the 18 us of encoding and 28 us of decoding left on head.
- The unchanged group is not a signal. It runs first in every process, while
  the window is still settling after its first paint, and its run medians
  swing between 7.6 and 18.8 ms on head and between 8.4 and 14.5 ms on trunk
  with p95 values of 26 to 48 ms on both sides.
- Request to first CPU content paint moves with the same noise (35 to 59 ms
  on both sides) and remains scene construction, not presentation.

## Limits

- CPU content paint and native dispatch are the last stages measured. No
  presentation or input-latency claim follows.
- The workload keeps the root identity and every node kind, so every head
  publication takes the operation path. Applications that replace the root or
  change a node's kind under the same ID still send whole descriptions.
- Native applies operations on a clone of the tree with a walk per operation;
  the dispatch stage includes that work and the full re-validation.
- Trunk and head ran one after the other rather than interleaved.
