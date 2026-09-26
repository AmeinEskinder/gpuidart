# Snapshot-heavy workload gate

The gate is demonstrated for a synthetic device-property inspector on Windows.
This is a scalability workload, not a claim that ordinary watchlist updates are
snapshot-heavy. The existing dataset update design remains unchanged.

`tool/performance/snapshot_fixture.dart` builds 128, 512 or 2,048 property text
nodes grouped into sections. Properties live in the description, not table data.
Each operation rebuilds fresh node objects. The input and 1k-row table are retained
state sentinels. Updates include unchanged publication, one property change,
reversal of sections, insertion and removal. No general node-patch implementation
was used to produce these captures.

## Collection

Normal release DLL from `e9c0c27`, Windows environment as in
`../baselines/windows-e9c0c27/windows-environment.json`. Three fresh JIT and AOT
processes per size, with rotated sizes and reversed mode order. The uncommitted
measurement tools at capture time are identified by `metadata.json` and saved
with this report. Native and AOT artifact hashes are included. All 18 runs and
all **720 snapshot replacements** passed. No ordinary update sent table records.
Input text/focus/selection, input/table entity identity and table scroll were
checked after every replacement. The final label values were also checked.

## Measured cost of one property change

Median of per-run medians across three AOT repetitions; microseconds except bytes:

| Property nodes | Bytes | Dart build | Describe | Encode/copy | Native decode/validate | Native dispatch |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 128 | 16,886 | 30.65 | 30.10 | 282.30 | 189.15 | 49.75 |
| 512 | 67,676 | 103.05 | 94.20 | 1,011.45 | 736.35 | 174.05 |
| 2,048 | 273,772 | 457.40 | 460.55 | 3,956.65 | 3,273.30 | 558.25 |

At 2,048 properties, unchanged publications still send approximately 273,771
bytes. They spend ~4,437.75 us encoding/copying and ~3,578.60 us decoding/validating.
These captures establish a workload where a small logical change incurs work
and transfer proportional to a large description. They support proceeding with
the requested experiment; they do not select a replacement protocol.

`statistics.json` retains all operation/size/mode groups. Eight samples per
operation make the reported within-run p95 the maximum; it is not a reliable
tail-latency estimate. Native parse currently combines decode and validation.
Native dispatch includes synchronous handling and acknowledgement submission.
Spans overlap. First content paint is matched to the snapshot revision and is
CPU work only. Whole-window draw histograms in raw reports mix operations and
must not be assigned to one operation. No presentation/input-latency claim.

## Next comparison

Compare equivalent snapshots, independently invalidated subviews and node patches
in an experimental build, keeping the production SDK protocol intact. Account
for mirror/staging trees, full-tree checks/copies hidden behind small messages,
layout/materialization, invalid/stale updates, rollback/resynchronization and
control identity. A faster experimental path still requires a separate production
decision. The comparison and its retained-state failure cases are not completed
by this gate.
