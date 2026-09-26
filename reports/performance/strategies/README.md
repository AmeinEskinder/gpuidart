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

Final local checks: all three strategy live runs at 128 fields passed; three
native experiment tests passed, including equal geometry. Repeated measurements,
platform results and adoption decisions will be recorded here after collection.
