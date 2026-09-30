# Operation update gate

Trunk-versus-head run of the snapshot gate for
[retained description updates](../../../docs/retained-tree.md). Trunk is the
unmodified `dev` head the change was built on (`e5345e5`). Head is `b3f0c56`,
which carries operation updates, the diff optimization, and the checkbox and
structural-edit commits that do not touch the publish path. An earlier head
run at `f5bc802`, before the diff optimization, is kept under `head-f5bc802`.
Both sides compiled their own AOT capture and their own release native
library, so each side runs its own SDK code end to end. `trunk/metadata.json`
and `head/metadata.json` record the source revision, a clean working tree and
the native library hash for each side.

## Method

This records the pre-migration command. For a new comparison, use
`dart run tool/performance/run_update_gate.dart`; its current arguments are in
the [performance guide](../../../tool/performance/README.md).

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
table checked after every publication. All 36 runs passed on every series.

Sides ran one after the other on the same machine in one session
(`environment.json`): trunk first, then the `f5bc802` head, then the `b3f0c56`
head with `-Sides head` against the same trunk series.

## Result, AOT

| Fields, operation | Metric | Trunk | Head | Head / trunk |
| --- | --- | ---: | ---: | ---: |
| 2,048 property | Bytes | 273,772 | 201 | 0.00 |
| 2,048 property | Describe, us | 399 | 510 | 1.28 |
| 2,048 property | Diff, us | | 1,252 | |
| 2,048 property | Encode/copy, us | 2,837 | 18 | 0.01 |
| 2,048 property | Native decode/validate, us | 3,176 | 28 | 0.01 |
| 2,048 property | Native dispatch, us | 541 | 1,222 | 2.26 |
| 2,048 property | Publish to ack, us | 7,197 | 3,317 | 0.46 |
| 2,048 reorder | Publish to ack, us | 7,742 | 4,526 | 0.58 |
| 2,048 insert | Publish to ack, us | 7,665 | 3,988 | 0.52 |
| 2,048 remove | Publish to ack, us | 23,652 | 3,680 | 0.16 |
| 512 property | Publish to ack, us | 2,059 | 1,048 | 0.51 |
| 512 reorder | Publish to ack, us | 1,850 | 1,105 | 0.60 |
| 512 insert | Publish to ack, us | 1,838 | 1,146 | 0.62 |
| 512 remove | Publish to ack, us | 1,866 | 827 | 0.44 |
| 128 property | Publish to ack, us | 690 | 626 | 0.91 |
| 128 reorder | Publish to ack, us | 736 | 335 | 0.46 |
| 128 insert | Publish to ack, us | 691 | 433 | 0.63 |
| 128 remove | Publish to ack, us | 611 | 372 | 0.61 |

Bytes per change are 73 to 941 on head at every size against 16,886 to
274,002 on trunk. JIT rows follow the same shape; see `comparison.md`.

Before the diff optimization (`comparison-f5bc802.md`), the 2,048-property
diff cost 2,765 us and publish to ack was 5,324 us (0.74 of trunk); the
optimization brought the diff to 1,252 us and the acknowledgement to 3,317 us.

## Reading

- The transfer and the two serialization stages are gone from the change
  path. What remains on head is the Dart describe plus diff, 1.8 ms at 2,048
  nodes, and a native dispatch that doubled because the update is applied on
  a clone of the tree and the result is validated in full.
- The Dart diff pairs children by position before touching a hash index, so
  the property workload never builds one; reorder and insert do, which is why
  their diff is 0.4 to 0.6 ms higher than property at 2,048 nodes.
- A binary wire would save at most the 18 us of encoding and 28 us of
  decoding left on head. The next native target is the clone plus full
  revalidation inside dispatch.
- The unchanged group is not a signal. It runs first in every process, while
  the window is still settling after its first paint, and its run medians
  swing by a factor of two on both sides with p95 values of 26 to 48 ms.
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

## Second run: in-place application

[`inplace-20260928/`](inplace-20260928/README.md) repeats the gate with the
merge commit `da40c23` as trunk and `96de75f` as head, which applies
operations in place against an ID index instead of cloning and revalidating
the tree. Native dispatch at 2,048 nodes fell to about a tenth for every
operation kind.

## Third run: cached subtrees

[`frames-20260928/`](frames-20260928/README.md) runs the gate at `051d79f`
with plain and with cached sections. The mixed workload's per-frame median
is flat because reorders move every cached section; a property-only run
shows the frame after an edit at about a fifth at 2,048 nodes.
