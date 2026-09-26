# Measured performance milestone

Work order accepted on 2026-09-26, starting from `6e8ee79`. This records the
owner's next milestone, roadmap steps 5–6. The earlier hardware observations,
macOS signing and historical Windows reload disposition remain parked. Work is
performed without subagents, with a commit for each completed milestone.

## Measurement contracts

1. Measure Windows x64, Ubuntu 24.04 x64/X11 and macOS 15 ARM64 independently.
   Record source, artifacts, toolchains, machine/display and instrumentation.
   Separate process launch, first Dart application instruction, dataset build,
   library loading, description/JSON/UTF-8/FFI copy, initial native decode and
   validation, runner startup, window creation and useful content painting.
   The paint boundary concerns CPU scene construction, not GPU presentation.
   Do not sum overlapping spans or percentiles.
2. Measure an empty host and increasing datasets in fresh processes. Keep OS
   memory metrics separate; record sampled peak and settled memory, allocation
   probe scope, and temporary buffers. Do not call process RSS sums unique
   physical memory or ascribe the whole difference to the Dart VM.
3. Quantify macOS application and UI processes separately, including initial
   transport and representative round trips. Use matched controls to identify
   what each difference can establish. Linux direct/companion runs can measure
   that platform's transport choice, not substitute for macOS measurements.

## Step-6 gate and experiment

First characterize a workload whose ordinary updates rebuild a substantial
description, including traffic and the cost by stage. Then compare whole-view
snapshots, independently invalidated subviews and node patches using equivalent
content and actions. Keep the experimental interfaces outside the production
SDK protocol. Account for Dart build/diff work, copied/transferred bytes, native
decode/validation/application, layout/paint, retained memory and staging memory.

Include unchanged publishes, property edits, insertion/removal, reordering and
retained-state checks. Malformed/stale updates, duplicate/reused IDs, failed
transactions and resynchronization must not silently corrupt retained controls.
Record whether a strategy validates or copies the entire tree even when its
message is small. A byte reduction alone does not establish a performance win.

## Decisions and completion

Optimize only stages implicated by the new captures. Every attempted
optimization has equivalent before/after measurements and a recorded keep or
revert decision; retain unsuccessful attempts. A production patch protocol is
a separate owner decision even if the experiment favors it.

No new widget kinds and no input-to-present or responsiveness claims. Completion
requires baselines and comparison evidence under `reports/`, roadmap/tracing
documentation updated to observed outcomes, Windows/macOS/Linux CI green at
the final commit, and a clean pushed tree.

## Progress

- Starting source audit: the old baseline covers one 100k fixture, three repetitions,
  window readiness and a later diagnostic repaint. Initial parsing occurs
  before trace enable; JSON/UTF-8/copy share one span. These do not yet satisfy
  the startup or allocation contracts above.
- Startup instrumentation: committed as `61c61b9`, with Windows/macOS/Linux and
  Unix lifecycle CI passing. Initial decode/validation and CPU content paint are
  now explicit. See [instrumentation checks](../reports/performance/instrumentation/README.md).
- Baseline harness: empty/1k/10k/100k, JIT/AOT, data/library/host controls,
  OS memory peaks and a separate Rust allocation-profile build implemented;
  debug Windows smoke passed. Windows/macOS/Linux release measurements and
  dedicated companion analysis are recorded. See [baselines](../reports/performance/baselines/README.md).
- Snapshot-heavy gate: demonstrated by 18 Windows runs / 720 retained-state
  checks at 128/512/2048 properties. See [gate evidence](../reports/performance/snapshot-gate/README.md).
  The three-strategy experiment has not yet been implemented.
- Measured optimization decisions and final CI: not started.
