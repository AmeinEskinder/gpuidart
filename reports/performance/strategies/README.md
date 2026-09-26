# Snapshot strategy experiment

The [snapshot-heavy gate](../snapshot-gate/README.md) justified this experiment.
This executable is behind `snapshot-experiment`; it adds no production SDK
operation, ABI change, widget kind or patch API.

## Contract

All strategies use the same Dart driver, Rust UI process, framed stdin/stdout
transport, GPUI materializer and native controls. This isolates experimental
protocol/rendering tradeoffs, **not shipping FFI transport performance**.
Each run has a retained input and 1,000-row table, plus 128/512/2,048 text
properties in sections of 32. A headless test compares actual control/text
bounds across strategies. Sections have fixed heights required by GPUI cached
views; this is a separate fixture from the content-sized gate.

- Whole snapshots rebuild/encode the tree and publish through one `DartView`.
- Independent subviews explicitly invalidate the affected section, using separate
  cached GPUI entities. Property edits assert that other sections do not rebuild.
- Patches build a fresh tree and run a Dart ID-based diff. Only text and structural
  edits with fixed kinds/styles are implemented. This is not a general SDK diff.

All strategies keep a global model and rendering descriptions. Subviews/patches
clone the full model for transactional staging and validate the whole candidate;
these costs are timed. The common fixture keeps source dataset storage as well
as the table copy. Its memory is not a production SDK baseline. Cached subviews
require fixed bounds and reject retained-control reparenting across owners;
the other strategies preserve state on reparenting. This capability difference
is part of the result, not hidden behind a passing check.

Three normal repetitions rotate sizes/strategy order and reverse JIT/AOT order.
Allocation profiling uses a separate executable and one repetition. Eight
updates each cover unchanged/property/reorder/insert/remove. Each acknowledgement
waits for a CPU paint of its revision and checks labels, input text/focus/selection,
entity identity and table scroll. Separate failure cases cover stale revisions,
duplicate IDs, atomic rollback, resync, ID removal/reuse and reparenting.

Build, description, diff, encode, framing/write, native decode/staging/validation/
application and CPU layout/prepaint/paint intervals are recorded separately.
`layout_gap_us` includes work between request-layout and prepaint; it is not an
isolated solver timer. Request/reply also serializes full diagnostic responses.
Neither it nor CPU paint measures presentation latency. OS memory remains split
by process and metric; the allocation probe excludes Dart/external/GPU allocations.
The Dart driver's memory includes fixture/mirror and collected evidence.

## Implementation checks and retained failures

`implementation/` retains commands and small live captures. Initial build failed
because `TableData` is not `Clone`; fixture copying was made explicit. Initial
geometry checks exposed a test macro glob-import collision, an invalid theme
token, and the fact that normal GPUI test bounds do not observe arbitrary text
or the table wrapper. The final test uses a test-only transparent bounds probe
and asserts all five nodes, rather than dropping missing assertions.

One geometry build exhausted Windows commit capacity (error 1455 / LLVM OOM).
Retrying only the library test with one Cargo job passed. System settings and
other applications were not changed. An analyzer attempt found three missing
brace-style requirements; these were fixed. Request/change enums were changed
to external tags before measurement so serde need not buffer an entire tree to
discover its message kind. Earlier live checks are correctness smoke only.

Two local allocation-profile builds subsequently reported `can't find crate for
gpui_kit`, despite the artifact existing. The host had only 653,060 KiB of free
commit capacity at inspection; the exact compiler failure was not isolated.
These attempts are retained and measurement moved to fresh hosted runners on
all three operating systems. Local correctness smoke is kept separate from the
hosted release measurements.

The first hosted Windows measurement job selected Git Bash's `link.exe` instead
of MSVC while building Rust dependencies. The workflow now records the MSVC
linker path from PowerShell before entering Bash. The failed job's output is
retained under `implementation/hosted-windows-attempt1`; no workload ran there.

Local checks: all three strategy live runs at 128 fields passed; three native
experiment tests passed, including equal geometry.

## Recorded series and decision

[Run 36253932588](https://github.com/AmeinEskinder/gpuidart/actions/runs/36253932588),
source `cbe8595`, passed on Windows Server 2022 x64, Ubuntu 24.04 x64/X11 and
macOS 15 ARM64. Each platform completed 54 normal runs and 18 allocation-profile
runs. Across the three platforms: **6,480 normal updates plus 2,160 profile updates**, all retained-state
checks passing. Each platform also passed 306 normal and 102 profile transactional/
lifecycle checks. A check that expects rejected cross-subview reparenting does
not establish support for that operation. Environment, hashes, raw captures,
command logs and separate analyses are in the three `*-cbe8595/` directories.

See [recorded stage and memory results](results.md). In the 2,048-property AOT
property-edit case, snapshot/subview/patch messages were 275,269 / 4,269 / 143
bytes. Subviews sharply reduced Dart preparation and cached native rendering.
Patches reduced transfer/decode work but still built/diffed the entire Dart tree,
cloned/validated the native model, and rendered the whole view. Their smaller
messages did not remove those costs.

Subview reordering has a different cost profile: prepaint medians rose to about
9.5–15.3 ms, versus 1.7–2.5 ms for whole snapshots on the same platforms. The
allocation-profile workload also requested more cumulative bytes with subviews
than snapshots on all three machines, despite low costs on property edits.
Memory readings are mixed, including a higher macOS footprint for subviews.
There is no universal memory or rendering winner.

**Do not adopt general patches in the production protocol.** Keep whole-view
snapshots and retained datasets. The fixed-section subview prototype is the more
promising option for this workload, but fixed bounds and explicit rejection of
cross-owner control moves prevent treating it as a transparent SDK replacement.
Any production subview API needs a separate design/acceptance decision. All
three experimental strategies remain reproducible behind an optional feature;
none is silently promoted into the SDK. These captures use the original two-stage
framed JSON encoder, before the separate direct-UTF-8 optimization.

The earlier Unix series from `ac17361` also passed and is retained separately in
`retained-attempts/`, not pooled with these repetitions. A local Windows series
ended after two successful cases when its tool session disappeared; no driver
completion record exists. Its partial files are retained with an explicit
incomplete marker. The runner now reports expected-run counts and completion,
and the summarizer refuses partial series. No failed application update was
excluded from a completed series.
