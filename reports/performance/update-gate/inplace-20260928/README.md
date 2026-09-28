# In-place operation updates: trunk versus head

Second trunk-versus-head run of the snapshot gate for
[retained description updates](../../../../docs/retained-tree.md). Trunk is
the merge commit `da40c23`, where native still applied operation updates on
a clone of the tree with a walk per operation and a whole-tree revalidation.
Head is `96de75f`, which applies operations in place against an ID and
parent index with an undo log and checks only what an operation can break,
and which describes the Dart tree against the previous description so
unchanged `UiNode` instances are reused. The gate fixture rebuilds every
node on every publication, so the reuse path finds nothing to reuse here
and only its bookkeeping shows; `tool/performance/bench_memo.dart` measures
the reuse itself. Both sides compiled their own AOT capture and their own
release native library; `trunk/metadata.json` and `head/metadata.json` record
the source revision, a clean working tree and the artifact hashes.

## Method

Same as the [first run](../README.md): `tool/performance/run_update_gate.ps1`
built release artifacts per side, ran `tool/performance/run_snapshot_gate.dart`
(three repetitions, sizes 128, 512 and 2,048 rotated, JIT and AOT, 720
state-preserving replacements in all) and summarized each series;
`comparison.md` is `tool/performance/compare_update_gate.dart` over the two
summaries. Trunk ran first in a detached checkout with its own target
directory and one build job, then head with two build jobs, both alone on
the machine during their measured runs (`environment.json`). All 36 runs
passed on both sides (`trunk/runs.json`, `head/runs.json`).

## Result, AOT, 2,048 nodes

| Operation | Metric | Trunk | Head | Head / trunk |
| --- | --- | ---: | ---: | ---: |
| property | Native dispatch, us | 1,254 | 132 | 0.11 |
| property | Publish to ack, us | 3,036 | 1,975 | 0.65 |
| property | Describe, us | 481 | 626 | 1.30 |
| property | Diff, us | 1,067 | 968 | 0.91 |
| reorder | Native dispatch, us | 1,200 | 188 | 0.16 |
| reorder | Publish to ack, us | 3,263 | 2,604 | 0.80 |
| insert | Native dispatch, us | 1,175 | 140 | 0.12 |
| insert | Publish to ack, us | 3,498 | 2,144 | 0.61 |
| remove | Native dispatch, us | 1,102 | 139 | 0.13 |
| remove | Publish to ack, us | 2,816 | 1,883 | 0.67 |
| unchanged | Native dispatch, us | 1,314 | 143 | 0.11 |
| unchanged | Publish to ack, us | 13,019 | 11,986 | 0.92 |

Bytes on the wire are identical per operation on both sides (201 for a
property change, 941 reorder, 132 insert, 73 remove, 41 unchanged), as are
encode, copy, decode and validate, all under 30 us.

## Reading

- Native dispatch, the stage the change targeted, fell to about a tenth at
  2,048 nodes for every operation kind, and to 0.40 at 128 nodes and 0.26 at
  512 nodes for a property change. The clone, the per-operation walk and the
  whole-tree revalidation were that cost.
- Publish to ack improved for every change kind at 2,048 nodes, 0.61 to 0.80.
  At 128 nodes it is dominated by scheduling noise: head's three run medians
  were 396, 3,004 and 1,230 us against trunk's 400, 632 and 714 us, with p95
  near 3 ms on both sides, while the dispatch stage inside them fell from
  127 to 51 us. Draw no conclusion from the 128-node publish figure.
- Describe rose by about a third at every size. The head describe walks the
  typed tree against the previous description, checking identity and
  matching children by position, which costs bookkeeping on a fixture that
  never reuses a node; the diff fell slightly, so Dart-side work is roughly
  unchanged in sum. Where an application keeps instances, the same walk
  turns into the reuse measured by `bench_memo.dart`.
- Request to first content paint moved both ways within about 13 percent
  and is not a claim of this change.
