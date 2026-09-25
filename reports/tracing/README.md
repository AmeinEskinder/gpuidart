# Publication tracing verification — 2026-09-25

Source: `b6a7ee0` (Dart API/tooling), following `5ef3901` (native trace extension).
The snapshot/dataset architecture is unchanged. See [usage and exact boundaries](../../docs/tracing.md).

## Completed checks

- 11 native tests passed, including trace bounds and FFI buffer ownership/status checks.
- 27 Dart tests passed, including real-window correlation, rejected requests,
  trace overflow, UI-content omission and optional-export compatibility checks.
- Dart analysis passed with fatal infos; Rust and Dart formatting passed.
- JIT and Dart AOT smoke workloads each uploaded 100,000 rows, completed 30 cell
  edits and 30 replacement snapshots, checked the final cell/revision and exported
  after shutdown. Each capture contains 848 records with no reported loss.
- All 61 subsequent requests per capture (30 dataset, 30 snapshot, one diagnostic)
  have one record for each checked stage: request, encode, native parse, enqueue
  attempt, dequeue, dispatch, emit, Dart receive and acknowledgement. Timestamp
  ordering is consistent within the documented one-tick cross-thread uncertainty.

[Verification metadata](verification.json) records source, runtime, artifact hashes,
byte counts, statuses and capture bounds. [JIT capture](jit.trace.json) and
[AOT capture](aot.trace.json) contain raw QPC records and Chrome Trace JSON.
Both use the **debug native DLL**, with tracing enabled. These are instrumentation
smoke checks, not a release performance comparison. No presentation measurement
or explanation of the historical acknowledgement tails is established.

Reproduction commands are in [the tracing guide](../../docs/tracing.md#reproduce-the-smoke-workload).

## Failures found while implementing the checks

1. The first full test run had two existing native-host tests fail at creation:
   the new live-window suite was running concurrently in another Dart test isolate.
   Loaded DLL state, including the one-host guard, is shared across these isolates.
   `dart_test.yaml` now serializes suites and retains the `live-window` tag so
   headless CI can exclude windows. The subsequent default test command passed all
   27 tests, including both live suites. No host guard was relaxed.
2. The first 100,000-row trace smoke verifier expected 30 snapshot acknowledgements
   but observed 31. The [retained capture](attempt-initial-ack-count.trace.json)
   contains revisions 1 through 31: initial application plus 30 publications.
   The verifier now counts replacement revisions greater than 1. The native trace
   test asserts both the initial snapshot acknowledgement and the separate ready
   acknowledgement. This was a verifier counting error; the native update path
   delivered the expected operations.

## Release status

This development milestone does not replace the packaged candidate recorded in
[the MVP report](../mvp/README.md). Clean-machine launch, human IME verification,
the [unlocalized reload observation](../mvp/attempt-023eef4/README.md), owner license
selection and first hosted CI execution remain open. Inspector RPCs, rendering and
presentation correlation remain future tracing work. The roadmap's snapshot /
subview / patch comparison still requires a demonstrated snapshot-heavy workload.
