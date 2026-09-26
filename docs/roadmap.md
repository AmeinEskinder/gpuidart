# SDK roadmap after boundary hardening

This evaluates the proposed feature-borrowing plan against source `ec24f6c` and the existing comparison records. It is a development recommendation, not evidence that any proposed feature has been implemented or measured. The release candidate keeps whole-view snapshots and revisioned native datasets.

## What the measurements establish

The [Dart/Shell/Solid comparison](../reports/comparison/dart-js-20260925.md) establishes a memory premium over the tested Shell implementation and lower private bytes and single-cell CPU than the tested Solid implementation. The separate [Rust/Dart comparison](../reports/comparison/rust-dart-20260925.md) measures the cost of the complete Dart integration. Neither isolates language-runtime overhead. These captures predate boundary hardening.

The 479–3,108 microsecond publication p95 values are from **incremental dataset messages**. All twelve Dart runs built one description at startup and encoded zero replacement snapshots. Cell runs transferred 7,524 bytes across 50 messages, about 150 bytes each. Native parse p95 was 24–50 microseconds and apply p95 was 7–12 microseconds across the reported cell/burst cases. The wide acknowledgement tails need correlated stage measurements; subtracting or adding percentiles cannot locate the delay. A node-patch protocol would not replace the dataset messages already being measured.

The 16 MiB snapshot limit is a validation ceiling. It is not the size sent for every update. The benchmark starts with a six-node description and a separate 3,788,261-byte dataset upload in the initial message. Later edits transfer only changed data.

The 462 / 305 / 277 ms Dart / Solid / Shell medians measure process launch to HWND discovery. They do not measure first displayed content or usability. Different startup paths prevent assigning the difference to Dart VM boot or excluding native initialization without traces. Native draw histories also have different collection windows and percentile estimators, so the existing figures cannot select an overdraw configuration or establish comparative smoothness.

The [payload measurements](../reports/comparison/README.md) describe explicit copied files, not complete installed footprints. Working set and private bytes remain distinct measures.

## Borrow these ideas with explicit boundaries

| Idea | Application to GPUI-Dart | Required boundary |
| --- | --- | --- |
| Trace events and inspector | Export publication stages, queue delay, callback delivery, startup stages and retained identities. Extend the existing diagnostic and VM-service mechanisms. | Opt in; bound retention; use request IDs and correlated clocks; avoid recording input text by default. Drawing and present submission remain separate from visible presentation. |
| Typed style data | Add a small validated layout/style structure to existing snapshots, mapped to GPUI layout and theme tokens. | Specify units, inheritance, precedence, bounds and supported properties. Patches are not a prerequisite. |
| Actions and keymaps | Expose a small typed action registry and scoped shortcuts. | Define focus context, propagation, shortcut conflicts, event delivery and disposal. Text editing and IME shortcuts require verification. A command palette still needs its own UI and focus behavior. |
| Stable record IDs and dataset views | Keep Dart authoritative for records; let Rust maintain filtered/sorted index views where useful. | Distinguish dataset revision, view revision and record ID. Preserve selection by record ID and scroll by an anchor plus offset. Specify what happens when the selected/anchored record disappears. |
| Declarative cell presentation | Evaluate bounded formatting, colors and icon mappings in Rust for visible cells. | Keep arbitrary Dart callbacks out of cell layout/paint. Define value types, formatter cost limits and accessibility text. Coverage must be demonstrated with application needs, not an assumed percentage. |
| Theme tokens and focused widget coverage | Make validated theme tokens replaceable and expose controls needed by the next representative screen. | Reuse GPUI Kit behavior while testing focus, overlays, keyboard interaction and semantics. Catalog breadth alone is not a release criterion. |
| Protocol schema generation | Generate wire models/codecs and documentation from one versioned schema as the protocol grows. | Keep ergonomic Dart wrappers and semantic/transaction tests. Generated types cannot prove lifecycle, ownership or update-order correctness. |

The pinned toolkit already has a separate [gpui-component-shell adapter](https://github.com/longbridge/gpui-kit/blob/21622a70efd25219d26aa459164878c4da9e39f8/crates/component-shell/src/lib.rs). That is the concrete component-catalog reference. Bare Shell remains independent of the component library. Its [inventory](https://github.com/longbridge/gpui-kit/blob/21622a70efd25219d26aa459164878c4da9e39f8/crates/component-shell/component-inventory.json) includes public modules, infrastructure and stories; inventory-entry counts are not interchangeable with supported widget kinds. Assess actual adapter behavior and properties when selecting bindings.

## Corrections to the proposed architecture

### Keys and patches solve different problems

Existing node IDs already preserve input/table entities across snapshot replacements. The table's records live outside that node tree and currently use row indices. Stable table selection after sorting/filtering requires record identity and index mapping, even if the table node never changes.

Position-derived node IDs can reduce typing for stateless content, but can attach retained state to the wrong item after insertion or reordering. Keep explicit identity for stateful and reorderable content. Retaining state across unmount/remount also needs lifetime, eviction and reset rules; it is not just an ID convenience.

[Flutter's identity shortcut](https://docs.flutter.dev/resources/inside-flutter#sublinear-widget-building) works when the same immutable widget instance is reused. GPUI-Dart's leaf constructors support const, but UiRow and UiColumn currently copy their child lists and are not const constructors. Rebuilding fresh objects does not automatically enable identity skips. Even when a patch contains only changed nodes, building and finding those changes can still visit the whole tree. Native validation, layout and materialization can also exceed the patch size.

[Fabric's mount phase](https://reactnative.dev/architecture/render-pipeline) computes mutations from committed shadow-tree versions. It does not establish that two independent diffs validate each other's correctness. If GPUI-Dart adopts patches, use one clear update protocol with a base revision, validation before mutation, atomic application, acknowledgements and a full-snapshot resynchronization path. Test malformed and stale batches, reordering, identity reuse, backpressure, reload and close during updates. Budget it as a protocol/lifecycle project.

### Event delivery must preserve application intent

An older snapshot revision does not by itself make an event invalid. Two clicks can be delivered from one rendered revision while processing the first click publishes a newer revision. Blanket revision filtering can discard the second valid click. Use control generations to detect disposal/recreation and dataset/view revisions for row-index interpretation.

Batch transport only with defined event semantics. Clicks and commands normally remain ordered and lossless. Some observations, such as pointer position, may allow coalescing. A once-per-frame batch can add waiting time, so it is not an automatic latency improvement. Controlled inputs require explicit text/selection/composition ownership and acknowledgement rules; preserve the native IME path during composition.

### Profile startup and memory by phase

Today gd_create parses initial JSON before the native runner opens its window. Moving that work to a GPUI background task requires a different startup lifecycle; it does not follow just from introducing AsyncApp. Showing an empty window sooner can improve HWND timing without improving time to useful content.

Measure external process launch, first Dart application code, record construction, DLL loading, initial encoding/copying, native parse/validation, runner startup, HWND creation, first useful draw and correlated presentation separately. Compare an empty screen and the 100,000-record screen with equivalent completion criteria.

The Dart FFI request buffer is freed in finally, and Rust retains parsed descriptions rather than a permanent raw JSON copy. Dart and Rust both retain dataset records by design. Measure the empty-host baseline, data-size slopes, temporary allocations, allocator retention and peak versus steady-state memory before attributing the premium to JSON or the VM. A Dart mirror tree or Rust staging tree can add retained memory. Sparse node patches would not eliminate the initial upload or the two record stores.

## Sequence and acceptance gates

1. Resolve the [unlocalized reload observation](../reports/mvp/attempt-023eef4/README.md) and complete [release checks](windows-release-checks.md). Keep hosted Windows CI passing; [the first runs succeeded](../reports/ci/README.md). The owner still needs to choose the SDK license.
2. Add correlated tracing and bounded inspection. Reproduce startup and publication costs with the current candidate. Instrumentation can proceed while external checks are unavailable.
3. ~~Add typed styles, a small action/keymap API and controls required by a representative screen, using the existing snapshot contract.~~ Implemented: typed styles `e957d44`, scoped actions/keymaps `135d300`, watchlist migration `1eafed0`.
4. ~~Add stable record identity, dataset views and declarative cell presentation. Prove selection/scroll rules through sort, filter, edits and reload at 100,000 records without republishing unchanged records.~~ Implemented: record IDs and views `e3238ca`, cell formatting `119217e`, watchlist migration `1eafed0`, 100,000-record evidence in [the feature-stack report](../reports/feature-stack/README.md).
5. Optimize the startup/memory stages identified by traces. Recheck CPU, both memory measures, peak allocations, payload and useful-content readiness on equivalent builds.
6. Evaluate general node patches only against a demonstrated snapshot-heavy workload. Compare whole-view snapshots, independently invalidated subviews and patches. Measure build/diff work, bytes, native validation/application, layout/draw and memory separately. Include unchanged publication, property edits, inserts/removes/reorders and retained-state failures. Require measured benefit on that workload without regressions before changing the production protocol.

Step 2 implementation: [opt-in publication tracing](tracing.md) now records correlated request stages with bounded buffers and Chrome Trace export. It does not yet provide inspector RPCs, rendering/presentation correlation, or an explanation of the historical acknowledgement tails. Steps 3 and 4 are implemented per the [feature-stack design](feature-stack.md) with evidence in [reports/feature-stack](../reports/feature-stack/README.md); the 100,000-row smoke workloads were re-run after these changes. Step 6 remains gated on a demonstrated snapshot-heavy workload.

Keep the current out-of-band dataset design. Shell's bridge limit explains the pinned benchmark's alternate table fixture; it does not invalidate all of Shell's host, registry or type-generation ideas. Per-cell application callbacks and per-signal crossings should be evaluated by call rate and measured cost rather than a claim that all FFI crossings are inherently prohibitive.

Correlated input-to-present measurement remains required for comparative responsiveness claims. Its absence does not prevent profiling and improving independently measured startup, CPU, allocation or publication costs.

The [macOS/Linux work order](cross-platform.md) starts with a separate feasibility gate for the pinned backends and Dart launch mechanism. It does not establish platform support or take priority over the open Windows release checks.
