# Native producer experiment

Status: proposed experiment, not an implemented binding API or a performance
result. Source baseline: `8f82364`. Production snapshots, datasets, event
acknowledgements and application-state ownership stay unchanged.

## Question and treatment

For an identical native event and visible cell update, what changes when the
producer executes on the GPUI foreground thread instead of round-tripping
through the Dart application? Measure event-to-native-state completion and
event-to-frame submission separately. Neither is visible-pixel latency.

The first prototype is Windows-only, behind an experimental build feature. Use
the existing benchmark driver, native GPUI Kit table, data, styling and viewport
rules. Other backends require their own submission hooks and verification.

| Arm | Producer and update route |
| --- | --- |
| A: current Dart application | Native event emits to Dart; Dart computes the value and publishes a revisioned cell edit through FFI and the command queue. Native validates/applies it and emits the existing acknowledgement. |
| B: native foreground producer | The same event entry computes the same value on the GPUI foreground thread and calls the shared native dataset application routine directly. It skips Dart value production, JSON/FFI submission and the command queue. |

Both arms use the same native semantic validation, data application, table
invalidation and renderer. B must not bypass those operations to make the
comparison faster. Use separate dataset identities and revision counters, with
matched visible tables, so B cannot invalidate A's Dart base revision. Keep both
tables mounted in every run and counterbalance their screen positions. This
two-table fixture is different from the historical single-table benchmark.

Factor shared state work from reply plumbing. B has no pending Dart transaction
and emits no fabricated Dart acknowledgement. Calling the current
`update_dataset` unchanged would emit an unmatched acknowledgement; that is not
a valid implementation of the comparison.

The experimental B dataset is native-owned after its initial upload; Dart must
not publish transactions against its stale copy. This explicitly changes where
the synthetic application logic and authoritative state live. It does not show
the benefit of a Dart-originated binding write, nor justify moving arbitrary
application logic into Rust. Queued native producers and Dart-originated bindings
are separate treatments, not interchangeable implementations of B.

### View dependencies are a workload factor

The primary pilot edits a column outside the configured view's sort/filter
columns. A separate workload edits a referenced column, so native view recompute
is included in `state_committed` for both arms. Do not pool these workloads.
Before either pilot, commit a manifest with the exact view definition, edited
columns, values, cadence, selected record, scroll anchor and expected visibility.
Verify the declared path using native view-recompute counters.

The referenced-column latency workload must keep the target visible. Exercise
selection disappearance and targets filtered out or moved outside the viewport
in separate correctness cases with explicitly expected outcomes. Such edits need
not produce a rendered value; record that reason instead of classifying them as
lost updates or assigning them a submission latency. Recompute-triggered selection
events can reach Dart in either arm. Preserve and count those events, and freeze
their listener behavior in the manifest. B bypasses Dart value production, not
necessarily every Dart callback.

## Common event and native endpoints

Give each delivered event a numeric sequence and arm at one native handler entry.
Record `event_origin` there before branching. That is the common start, excluding
OS input injection and delivery. Retain driver planned/injected/delivered counts
and timestamps separately. The value computation is deterministic in both arms;
verify its equivalence, including the expected resulting cell value.

Add a trace-only `native.state_committed` point inside the shared successful
application path: after accepted data and required derived-view updates and
invalidation, before acknowledgement serialization/submission. It measures
completion of the native state work needed for rendering. Emit no success marker
on rejection. Correlate it to event sequence, request, dataset and new revision
using numeric experiment IDs. No `DatasetApplied` wire change is required.

`DatasetApplied.parse_us` and `apply_us` are durations. `native.dispatch.end`
is a monotonic-clock timestamp at handler completion, after acknowledgement
serialization and callback submission for this path. It is not the commit point
and must not be compared to B's earlier version bump. Keep dispatch completion
as a separate metric; preserve A's real acknowledgement and measure it separately.

Report A's acknowledgement work alongside the shared endpoints in the main
results table, not only in an appendix:

| Interval | Reported meaning |
| --- | --- |
| Event origin to state committed, A and B | Completion of native state work |
| State committed to `native.emit`, A | Remaining work through acknowledgement serialization |
| State committed to dispatch end, A | Remaining handler work, including callback submission |
| `native.emit` to `dart.receive`, A | Reply delivery interval |
| `dart.receive` to `dart.ack`, A | Decode, validation and acknowledgement handling |
| Event origin to `dart.ack` and to `dart.commit`, A | Acknowledgement and authoritative Dart dataset completion, respectively |

Report rejection/missing-ack counts and sample denominators. These intervals can
overlap; do not sum them or their percentiles. B's absent transaction/acknowledgement
is not applicable, not a zero-duration observation. Keep native-state differences
separate from A's post-state completion costs and from semantic selection events.

## Causal analysis and capture validity

Use all observed `(process, thread)` timelines plus logical event/request edges,
not a fixed pair of physical threads. A Dart isolate can resume on another OS
thread. Synchronous spans are nested; buffers store durations when they end, so
append order is not start-time order. Analyze timestamped endpoints and nesting.

Keep these intervals distinct, including all uncategorized time:

* Event origin to Dart callback, Dart preparation, encoding/copy and FFI call.
* Successful `native.enqueue_attempt` to matching `native.dequeue`.
* Native dispatch, state completion and reply serialization/submission.
* `native.emit` to matching `dart.receive`, followed by decode/ack handling.
* Event origin and state completion to the correlated frame milestones below.

These intervals overlap. Do not sum their durations or percentiles. Dequeue
before FFI return and receipt before dispatch end can be valid concurrency. In
contrast, dequeue before its matching enqueue attempt, or receipt before its
matching emit marker, violates a causal edge beyond the documented clock
uncertainty. Investigate pairing, clock domains and instrumentation; do not
reinterpret those negative intervals as consumer progress. QPC's documented
one-tick ordering allowance does not establish Unix clock uncertainty.

Validate event/request identities, expected marker multiplicity, causal edges,
span nesting, statuses, trace-read success and finalization. A telescoping sum
is not an independent consistency check. Preserve unmatched requests and failed
attempts; never silently filter them into a successful-run sample.

Use capacity 8192 initially and measure records per arm/phase during the pilot.
Capacity applies to Dart and native separately. On macOS each native process is
bounded, and the merged native export is also capped at the configured capacity;
two native processes do not double usable exported capacity. Split captures if
needed, budget startup/shutdown, and require zero dropped records for attribution.
Retain incomplete captures as failed measurement attempts, including failure
counts. Never exclude an application failure merely to improve latency samples.

## Rendered values and frame submission

At the point a target visible cell's value is consumed for rendering, record its
dataset/cell version and originating event. Carry that record with the exact
frame/scene through submission. Do not read a newer current revision when the
present call runs. The snapshot revision alone cannot identify dataset edits.
Record frame IDs and relevant per-cell versions, not all 100,000 records.

Keep CPU `content_paint`, GPU submission, present-call entry and successful
`present_call_completed` separate. The latter is a submission milestone with the
exact frame association and return status, not a fence proving displayed pixels.
Record attempts, failures, occlusion/skips and frames abandoned before submission.
A successful call can still precede a dropped frame downstream. If the backend
cannot provide a trustworthy frame-to-submit association, report this endpoint
as unavailable and finish only the native-state portion of the experiment.

Classify each update's outcome explicitly:

* State rejection or application failure.
* Committed, then superseded for that cell before a frame consumed it.
* Consumed in a frame but never successfully submitted during observation.
* First successfully submitted frame that consumed the update's value, with its
  frame ID and timestamp.
* Outstanding/unknown at the defined end of observation.

Distinct-cell edits can share a frame. A later update to another cell must not
mark an earlier surviving value superseded merely because the dataset revision
advanced. Same-cell values overwritten before consumption have no submission
latency sample. Keep their count and denominator beside the conditional latency
distribution; a path that coalesces more work must not appear better simply
because its omitted updates disappeared from the analysis.

Native readback checks retained state. Per-frame value/version records check
what rendering consumed; sampled captures can support visual spot checks. Neither
establishes that every intermediate value became visible. Future OS presentation
feedback requires frame correlation and separate scope, with no assumed bound on
compositor/display delay. No macOS IME or physical-display claim is part of this
experiment.

## Schedule, repetition and decisions

Use balanced randomized A/B order within short blocks in one process, with saved
seeds and independent process runs. Set each arm's intended event rate explicitly;
alternating an aggregate 5 Hz stream would give each arm only 2.5 Hz. Never wait
for A's acknowledgement before scheduling B. Record backlog, contention, missed
driver slots, delivered events, failures and supersession. A's work can affect B
through the shared UI thread; add isolated-arm control runs before attributing a
result to a removed stage. Pairing in time does not eliminate interference.

Pre-register paired analysis: for each workload and endpoint, compute the arm
means within each balanced block and their signed difference, B minus A. Average
block differences within each run, then summarize across independent runs. This
is the primary latency contrast; do not replace it after inspection with an
unpaired pooled comparison. Report per-arm eligible counts, failures and
supersession alongside each contrast. An endpoint with no eligible samples in
one arm has an unavailable block contrast, not a zero or a silently omitted
block. Retain all blocks in the outcome accounting. For uncertainty, resample
independent runs while preserving their blocks and A/B assignments; do not treat
individual events as independent replicates. Per-arm median/p95/p99 summaries
remain secondary and retain their workload/run scope.

Match cell counts and value transformations between arms. Treat event cadence
and cells per event as separate workload factors. A 200 ms interval is not proof
of cold execution, and a 33 ms interval is not proof of warm execution. Historical
cell/burst p95 results have no consistent inversion and are not a causal baseline.
All new measurements are instrumented; do not compare their timings directly
with the historical uninstrumented series.

At least 200 delivered events per arm per exploratory workload is a starting
sample, not a sufficient p99 estimate. Report repeated-run distributions and
uncertainty with run/block dependence retained. If exploration suggests classes
or a mechanism, define them from measured evidence and freeze them before new
confirmatory captures. Do not select classes from the desired outcome.

Before confirmation, commit the exact producer placement, workloads, rates,
sampling plan, exclusion rules, endpoints, practical benefit threshold and
correctness/CPU/memory regression limits. Keep all failed attempts and any reverts.
Adopt no public binding API through this experiment. A measured improvement is
specific to this native-producer placement and matched fixture; a production API
proposal must separately address ownership, lifetime, reload, backpressure and
the other platform process models. An unavailable submission hook or inconclusive
result is recorded as such, not treated as evidence for or against visible latency.

## Source anchors

* [Tracing contract](tracing.md): overlap, clocks, bounded buffers and capture scope.
* `native/src/ui.rs`, dataset application and command loop: state updates precede
  event emission; the dispatch guard outlives command handling.
* `native/src/lib.rs`, event callback: JSON serialization precedes `native.emit`.
* `native/src/trace.rs`, Dispatch and import_remote: completion and merged bounds.
* [Historical publication results](../reports/comparison/dart-js-20260925.md): all
  three cell/burst repetitions, with explicit percentile and workload limitations.
