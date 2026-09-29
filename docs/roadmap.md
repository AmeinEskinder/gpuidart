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

The pinned toolkit already has a separate [gpui-component-shell adapter](https://github.com/longbridge/gpui-kit/blob/0c830f4d257e69fdd17200650533ab4ca9a40cc0/crates/component-shell/src/lib.rs). That is the concrete component-catalog reference. Bare Shell remains independent of the component library. Its [inventory](https://github.com/longbridge/gpui-kit/blob/0c830f4d257e69fdd17200650533ab4ca9a40cc0/crates/component-shell/component-inventory.json) includes public modules, infrastructure and stories; inventory-entry counts are not interchangeable with supported widget kinds. Assess actual adapter behavior and properties when selecting bindings.

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

1. Resolve the [unlocalized reload observation](../reports/mvp/attempt-023eef4/README.md) and complete [release checks](windows-release-checks.md). Keep hosted Windows CI passing; [the first runs succeeded](../reports/ci/README.md). The owner selected the [MIT License](../LICENSE) on 2026-09-26.
2. Add correlated tracing and bounded inspection. Reproduce startup and publication costs with the current candidate. Instrumentation can proceed while external checks are unavailable.
3. ~~Add typed styles, a small action/keymap API and controls required by a representative screen, using the existing snapshot contract.~~ Implemented: typed styles `e957d44`, scoped actions/keymaps `135d300`, watchlist migration `1eafed0`.
4. ~~Add stable record identity, dataset views and declarative cell presentation. Prove selection/scroll rules through sort, filter, edits and reload at 100,000 records without republishing unchanged records.~~ Implemented: record IDs and views `e3238ca`, cell formatting `119217e`, watchlist migration `1eafed0`, 100,000-record evidence in [the feature-stack report](../reports/feature-stack/README.md).
5. Optimize the startup/memory stages identified by traces. Recheck CPU, both memory measures, peak allocations, payload and useful-content readiness on equivalent builds.
6. Evaluate general node patches only against a demonstrated snapshot-heavy workload. Compare whole-view snapshots, independently invalidated subviews and patches. Measure build/diff work, bytes, native validation/application, layout/draw and memory separately. Include unchanged publication, property edits, inserts/removes/reorders and retained-state failures. Require measured benefit on that workload without regressions before changing the production protocol.

Step 2 implementation: [opt-in publication tracing](tracing.md) now records correlated request stages with bounded buffers and Chrome Trace export. It does not yet provide inspector RPCs, rendering/presentation correlation, or an explanation of the historical acknowledgement tails. Steps 3 and 4 are implemented per the [feature-stack design](feature-stack.md) with evidence in [reports/feature-stack](../reports/feature-stack/README.md); the 100,000-row smoke workloads were re-run after these changes. Step 6's workload gate and experimental comparison are now complete; production protocol changes remain a separate decision.

Keep the current out-of-band dataset design. Shell's bridge limit explains the pinned benchmark's alternate table fixture; it does not invalidate all of Shell's host, registry or type-generation ideas. Per-cell application callbacks and per-signal crossings should be evaluated by call rate and measured cost rather than a claim that all FFI crossings are inherently prohibitive.

Correlated input-to-present measurement remains required for comparative responsiveness claims. Its absence does not prevent profiling and improving independently measured startup, CPU, allocation or publication costs.

Steps 5–6 measurement update (2026-09-26): [release baselines](../reports/performance/baselines/README.md)
now cover empty/1k/10k/100k fixtures, JIT/AOT, application/library controls, separate
allocation-profile builds and the macOS companion. A [snapshot-heavy inspector](../reports/performance/snapshot-gate/README.md)
passed 18 runs / 720 state-preserving replacements and demonstrates costs that
scale with description size for one-property changes. This opens the experiment
gate. The [three-strategy comparison](../reports/performance/strategies/README.md)
completed 162 normal and 54 allocation-profile runs on three platforms. Cached
subviews reduce property-update work in the fixed-section fixture, with reorder,
allocation and state-migration tradeoffs. Patches reduce bytes but retain full
build/diff, staging/validation and rendering work; they were not adopted as
prototyped. [Retained description updates](retained-tree.md) later replaced
whole-snapshot publication with operations applied to the tree native already
holds, gated by the same snapshot-gate workload at trunk and head. The dataset
protocol remains unchanged.

Step 5 outcome: [keep direct UTF-8 JSON encoding](../reports/performance/encoding/host-results.md).
Matched host captures reduced the 100k AOT encode/copy stage on all three
platforms. Memory and payload tradeoffs are recorded; no presentation or general
runtime-superiority claim follows. Additional startup/process-model changes were
not justified by this milestone. The macOS companion's measured costs remain
separate from hypothetical shared-process alternatives.

The [macOS/Linux work order](cross-platform.md) starts with a separate feasibility gate for the pinned backends and Dart launch mechanism. It does not establish platform support or take priority over the open Windows release checks.

Control-catalog follow-up: [the settings design](control-catalog.md) selects four
controls from an actual preferences screen. Checkbox `cddca71`, slider `07bfccf`,
select `35cf74d`, confirmation dialog `3014d31`, controlled inputs `edc8dab`, and
the settings application/verifier `3ec8a87` are implemented. The
[evidence report](../reports/control-catalog/README.md) records their tests and
retained failures. [Schema generation is skipped for now](protocol-schema-decision.md)
with a defined future equivalence gate. This does not expand the production
snapshot protocol into patches or close the parked hardware/IME/signing gates.

Accessibility follow-up: [the semantics model and native adapters](accessibility.md)
are implemented and the external UIA/AT-SPI/AX track passes on all three hosted
platforms. Settings verifies all 15 steps through the OS tree; Watchlist verifies
viewport-bounded table semantics and stable-record selection through sort/filter
over 100,000 records. [The evidence](../reports/accessibility/README.md) retains
provider defects, verifier failures and the narrow pinned dependency corrections.
Human screen-reader sessions, offscreen virtual-table navigation, Linux EditableText
and live announcements remain outside the verified surface. This milestone does
not close the parked release gates or justify a production patch protocol.

Market-terminal follow-up: [themes, navigation and charts](navigation-and-charts.md)
are implemented without changing the snapshot/dataset architecture. The
[terminal](../example/terminal/README.md) uses light/dark/custom token palettes,
tabs, radios, native/in-window application menus, record-bound row menus, button
tooltips and bounded dataset line/bar charts. The [acceptance report](../reports/market-terminal/README.md)
records 100k JIT/AOT interaction, external UIA/AT-SPI/AX checks and actual Dart-code
reload on three platforms, with retained failures and narrow dependency patches.
Editor binding, general virtual lists, presentation correlation and parked human
hardware/signing checks remain separate work. No public patch protocol is adopted.

## Framework delivery status (2026-09-27)

The owner's ten-move plan toward Flutter parity was executed in the order the
evaluation recommended: retained tree first, measured before any wire change,
then value ownership for controls, then datasets, then catalog breadth, then
windows. Each move landed as verified commits on `dev`:

| Move | Outcome | Commits |
| --- | --- | --- |
| Retained description updates | Dart diffs against the previous tree and sends operations; native applies them atomically with full validation and stale-base resubmission. Measured on the snapshot-gate workload: a 2,048-property change fell from 273,772 to 201 bytes and publish-to-ack from 7,197 to 3,317 µs. | `61de8e1`, `06466d8`, `3b6c03d`, `b3f0c56`, reports `34fc39a`, `1925f9b` |
| Binary wire | Deferred with evidence for the description path: after operations, encode and decode are microseconds; the remaining cost is Dart describe/diff and native clone/revalidation, not JSON. Bulk record transfer is packed: an appended slice is a JSON header followed by its cells and record IDs as length-prefixed UTF-8, native stores and acknowledges each slice and recomputes the views once at the last, record IDs are checked against a sorted hash index, and Dart packs a slice while native applies the previous one. At one million records the open fell from about 3.1 s with 13 recomputes to 1.15 to 1.86 s with one, per-slice apply from 79 ms (p99 296) to 12 to 20 ms (p99 41) and submit to acknowledgement from 200 ms to 68 to 110 ms; native parse on the calling thread, 33 to 60 ms of string allocation per slice, is what remains and would need the typed-cell change. | [update gate](../reports/performance/update-gate/README.md), [one million records, JSON](../reports/performance/datasets-1m-20260928/README.md), [packed](../reports/performance/datasets-1m-20260929/README.md) |
| Control value ownership | Controls show the interaction at once; the next publication is authoritative. Checkbox, switch, list. Radio groups and tabs use the retained implementations from `main`. | `364a789`, `c7e3554`, `ace3fcc` |
| Datasets 2.0 | Structural edits (insert, delete, move) with running-shape validation, deferred record upload, grouped views with native aggregates, and virtualized lists over a column. The row cap is 1,000,000: records beyond about 4 MiB of encoded text upload as a schema and packed appended slices (`append` on the wire) behind `open`, `registerDataset` and `replaceDataset`, one revision per slice and one view recompute at the last. Cells are still strings. Dart keeps its own copy of the records unless the dataset is constructed with `retainRecords: false`, which releases it after the upload and leaves identity checks to native; at one million records that returns about 230 MiB of process memory beside the native 250 MiB. | `f535cb0`, `bda6589`, `04cc914`, `ace3fcc`, [datasets](datasets.md), [one million records](../reports/performance/datasets-1m-20260928/README.md) |
| Layout | Flex growth, min/max sizes, stacks with insets, scroll containers with retained offsets. | `934c102` |
| Catalog | Switch, progress, separator, canvas draw lists, native animation, menu buttons over application menu entries, native file/save/URL/reveal requests; tabs, radio groups, tooltips, application and context menus, themes and charts come from `main` through the merge. Icons from the bundled Lucide catalog by name, images from a file path or inline bytes fitted into their bounds, and a calendar date picker under the settings contract followed on 2026-09-28; resizable panes, a tree, a popover, a sheet, searchable selects (the combobox) and rich text on 2026-09-29, and the market terminal rebuilt on them ([track 4](market-terminal.md#track-4-the-widened-catalog-2026-09-29)). The [binding table](binding-table.md) lists every Kit component against the kind that binds it: twenty-nine kinds reach about a third of the catalog, and the six the catalog plan named are bound. | `c7e3554`, `c73ecce`, `8d602c4`, [control catalog](control-catalog.md), [binding table](binding-table.md) |
| Multi-window | Secondary windows with their own descriptions, datasets, revisions and events, addressed through window-aware exports. | `890e20a` |
| Retained tree, second half | Operation updates apply in place against an ID and parent index with an undo log, checking only what an operation can break; the clone and whole-tree revalidation are gone. Measured by the update gate at the merge commit against this head: native dispatch at 2,048 nodes fell to about a tenth for every operation kind and publish to ack to 0.61 through 0.80 of trunk. | `e1a5610`, [report](../reports/performance/update-gate/inplace-20260928/README.md) |
| Retained tree, render half | `UiStyle.cached` keeps a container's rendered subtree across frames as its own GPUI entity; frames touch it again only when an operation, a dataset it shows or a whole publication changes it. After property edits at 2,048 nodes the frame fell from 32.8 to 6.6 ms with untouched sections rendering no further times; reorders, inserts and removes render moved sections again and cost 11 to 30 percent on those publications. | `051d79f`, [report](../reports/performance/update-gate/frames-20260928/README.md) |
| Signals | `6305ea7`. Delivered as identity reuse: describing against the previous description reuses unchanged `UiNode` instances and the diff skips them, with `UiMemo` keeping subtrees while their inputs are equal. At 2,048 fields, describe fell from 1,688 to 100 µs and diff from 2,099 to 278 µs (JIT medians, `bench_memo.dart`). `patch` then writes one node as a single set operation with no build, describe or diff at all. A reactive dependency graph was not built; memoized subtrees and bound writes give the sublinear rebuild it was for. | [retained tree](retained-tree.md) |
| Input-to-present | `b253dce`. Response-frame correlation: diagnostic builds record the first content paint of each applied revision, and the input analyzer joins it to the first PresentMon record of the process, reporting input to present start and to display. Verified on a synthetic trace and present capture. A live ETW capture needs administrator access or Performance Log Users membership, neither available on this machine, so no measured latency is recorded. A Flutter Windows fixture now runs in the same harness: two three-repetition series against the Dart fixture show Dart's working set 34 to 43 MiB lower and, on the click workloads, CPU within a few percent of a core once Flutter's button ripple is off; the scroll runs in those series missed driver deadlines on both sides and sit outside the equal-work subset (the driver's own interpreter stall, since removed: with the warmed driver Flutter met the cadence in three of three scroll runs and Dart in four of six, one Dart run retained for a 276 px scroll drift in the Kit table), and presentation latency is unmeasured for both. With the Dart fixture opening its window before the upload (`deferDatasets`, measured 2026-09-29) its window handle appears at 255 ms median against Flutter's 64 ms, but the handle is not a frame: measured from a driver-side content probe and from each fixture's own clock, Dart's first painted content arrives about 0.2 s after launch with no records and 0.3 s with 100,000, Flutter's about 1.4 to 1.5 s ([capture](../reports/comparison/startup-20260929.md)); the zero-row launch-to-first-content row of the exit table is met by measurement, so the platform prewarm stays an option rather than a need. | [benchmarks](../benchmarks/README.md), [comparison status](../reports/comparison/README.md) |
| Process model | The GPUI loop now runs on a dedicated 64 MiB-stack thread; the 1 MiB Dart isolate stack overflowed under unoptimized table rendering and crashed the VM. | `7b7cd0d` |
| Build environment | Worktree builds resolve a junctioned `.tools`. | `e558f12` |
| Startup | Trace points split the time before the first window: GPUI application construction was 125 to 147 ms of a 175 ms zero-row host-ready, and a raw probe attributed 85 to 163 ms of it to DirectWrite's first system font enumeration with its update check on. The vendored Windows platform crate now fetches the startup collection without that check (fonts installed later are still seen, with latency; the lookup-miss path keeps the immediate check). Zero-row host-ready fell from 175 to 118 ms median and 100,000-row from 232 to 140 ms on the same machine minutes apart; the D3D11 device, DXGI factory and window creation remain. Memory is untouched: the probe attributes about 35 MB of the 94 MB zero-row private commit to the D3D11 device's driver state and 13 MB to the Dart runtime, with the rest in window surfaces, atlases and heaps. | [startup report](../reports/performance/startup-20260928/README.md) |
| Toolkit pin | GPUI Kit moved from commit `21622a70` (0.6.5) to v0.7.0 (`0c830f4d`), and the vendored `gpui-pre` from 0.3.6 to 0.3.7 with the focus and window-bounds patches re-applied and re-hashed. The 51 upstream commits between the pins are rendering and component performance work, menu leak fixes, table cell rendering and chart painting speedups; no SDK source changed, and the full check gate passed unchanged. Baselines and gate reports taken before this pin remain labelled with the old revision. | [vendor provenance](../native/vendor/README.md) |

Feasibility verdicts recorded on this machine:

- **Embedding the Dart runtime in the native executable** is deferred, not
  ruled out. It needs the Dart SDK built from source for the embedder API
  (the C++ toolchain that was missing is installed since 2026-09-28, the
  multi-hour SDK build and its source tree are not) and a patched quit path
  in the vendored macOS platform. The launcher and companion process model
  stays until that build is worth its time.
- **A Flutter Windows fixture for side-by-side measurement** was blocked
  until 2026-09-28 by the missing C++ toolchain. With Visual Studio 2022
  Build Tools 17.14 installed the fixture is built and measured; the two
  series and their qualifications are in the
  [comparison status](../reports/comparison/README.md).
- **The memory floor holds at the widened catalog.** An almost empty host
  (one window, one text node) settles at 75 to 77 MiB of working set and
  91.5 MiB of private commit at this head, level with the 75.87 and 94.57 MiB
  of the `e9c0c27` baseline and under the 85 MB line the order of play set
  ([floor report](../reports/performance/floor-20260929/README.md)). The
  Windows runtime probe lists every mapped image (the graphics driver's
  shader compiler maps 82.7 MiB, the native library 25 MiB built with
  link-time optimization, the Direct3D driver 17 MiB) and walks the working
  set to say which pages are resident: 34.7 MiB of the floor sit inside the
  images, 4.9 of them the native library's and almost all of it shared with
  other processes, and 39 MiB are private heap outside every image.
- **View recomputes parse each column once.** The view workload's first
  series ([report](../reports/comparison/view-1m-20260929.md)) put the Dart
  fixture at about half the Flutter fixture's time per view change, and its
  probe showed why the native sort had looked cheap: the fixtures' prices
  rose with the row index, and a real descending sort over a million
  permuted prices took 5.4 to 7.5 s because the comparator parsed both cells
  on every comparison. Columns are now parsed once per recompute, a single
  numeric key sorts beside its rows, and aggregates fold in one pass: the
  same probe reads 149 to 164 ms for the sort, 148 to 184 with the filter and
  403 to 549 grouped. The earlier "sort recompute at about 110 ms" figures
  in this document were measured on ordered prices.
- **Typed dataset cells** stay deferred: sort, filter and aggregates already
  compare numerically when a cell parses as a number, formats render
  numbers from strings, and a recompute now parses each referenced column
  once (a million permuted prices sort in 149 to 164 ms), so a typed wire
  form would save that parse and the string memory rather than change
  behavior. It is a protocol change on both
  sides and waits for a workload that needs it.
- **Starting the GPUI platform before `gd_create`** would overlap the D3D11
  device and DirectWrite setup (about 50 ms after the font patch) with the
  Dart side's record building and encoding, which is 6 ms at zero rows and
  45 to 60 ms at 100,000; the gain is bounded by that Dart work, and the
  launch-to-first-content capture of 2026-09-29 puts Dart at about 0.2 s
  against Flutter's 1.5 s, so it is recorded as an option rather than built.
- **Native dialogs** are wired but not covered by headless tests; the test
  platform leaves the prompts and reveal unimplemented, so they are verified
  by manual runs only.

### Order of play after the fourth audit (2026-09-29)

The reviewer's order of play named ten moves and an exit table. Each move
below carries its state and the commit or report that shows it.

| Move | State | Evidence |
| --- | --- | --- |
| A, docs drift gate | Met. The check gate fails when the README, the SDK doc or this document drift from the code. | `4d9a0d6`, `tool/docs_check.dart` |
| B, scroll runs eligible for equal work | Met for the driver: Flutter 3 of 3 runs eligible, Dart 4 of 6, with one Kit scroll displacement drift retained as a Dart-side finding. The drift is resolved: the trace build records each wheel event at GPUI's door with its sequence and pointer position beside each painted offset, ten traced runs were exact, and the eleventh caught the drift as foreign input, a pointer moved by someone at the machine 2.7 s into the run, after which Windows routed 191 injected events to the window under the cursor and 7 reached GPUI off the table; the table moved exactly once per event it was given. The driver now stops a run whose pointer has moved, as it does on focus loss. | `f413815`, `e0075b3`, [scroll cadence](../reports/comparison/scroll-cadence-20260929.md) |
| C, presentation capture on both sides | Blocked on the owner: PresentMon needs Performance Log Users membership or an elevated session. | |
| D, launch to first painted content | Met by measurement: Dart 240 ms against Flutter 1,510 ms at zero rows by the driver's clock, 194 against 1,504 by the fixtures' own. | `8aef122`, [startup](../reports/comparison/startup-20260929.md) |
| E, packed record slices with one recompute | Met with a miss: two recomputes against thirteen (the deferred schema counts one), and the 1.5 s open met on the quiet runs and missed by up to 0.4 s on loaded ones (1.15 to 1.86 s over six); released-copy memory unchanged, retained-copy 30 to 40 MiB above a single earlier run. | `cab7c41`, [one million records](../reports/performance/datasets-1m-20260929/README.md) |
| F, sort, filter and group at a million rows | Measured, exit line not met: the Dart fixture completes view changes in about half the Flutter fixture's time, not a tenth. The series exposed the native comparator parsing per comparison (a real sort 5.4 to 7.5 s); columns now parse once (149 to 164 ms in the probe). The series on permuted prices is the next capture. | `f0c8f43`, `47ea24b`, [view workload](../reports/comparison/view-1m-20260929.md) |
| F2, the recompute off the frame thread, jank instead of throughput | Met as "no gap over two frame intervals": a view over 10,000 records computes on a worker thread over a snapshot of the records, the publication is acknowledged in 0.2 ms, edits sent meanwhile queue behind the swap, and the window keeps painting; over 36 million-row view changes with the pointer moving at 60 Hz the Dart fixture's longest gap between painted frames was 35 ms, two intervals at 60 Hz (six changes skipped one frame, none more; the audit's "zero over 33 ms" is missed by those six, at 33 to 35 ms), against 509 to 1,011 ms on the Flutter fixture, which paints nothing while its isolate sorts. The index lands 125 to 179 ms after a sort click and 340 to 450 ms after a grouping, 2 to 4 times faster than the Flutter handler, as the throughput series found. | `bfcbd53`, `a65d5fa`, [jank](../reports/comparison/view-jank-20260929.md) |
| G, binding table, six kinds, terminal | Met for the kinds and the terminal: panes, tree, popover, sheet, searchable select as the combobox, rich text (twenty-nine kinds), the terminal rebuilt on them with the accessibility workflow green. The "binding table" is a document mapping Kit's modules to kinds, not a generator; every kind is still bound by hand in the protocol, the materializer, the Dart node and the docs. The fifth audit withdrew the generator from the critical path. | `62653d1` to `aaa7cff`, `b38dc6b`, [binding table](binding-table.md) |
| H, memory floor under 85 MB or attribution | Half met on the number, met on the attribution: the working set of 74 to 77 MiB is under the line and the private commit of 91.5 to 92.2 MiB above it. A working-set walk now attributes the resident pages: 34.7 MiB inside the 69 mapped images (the native library 4.9, the graphics stack about 8, almost all shared with other processes) and 39 MiB of private heap outside every image, the Dart runtime's, the window's and the driver's allocations. | `7a99693`, `fef037d`, [floor](../reports/performance/floor-20260929/README.md) |
| I, embedding spike | Blocked on a machine for it. | |
| J, checkmate capture | Blocked on C. | |

Against the exit table: launch to first content is inside 1.5x of Flutter
(D); working set and private bytes are below Flutter's at 100,000 rows
(the comparison series) and above them at a million rows only while the
fixture keeps its Dart copy of the records; a million-row view change no
longer stalls the window (longest gap 35 ms against Flutter's 509 to
1,011 ms) and lands its index 2 to 4 times sooner than the Flutter
handler, not an order of magnitude (F, F2); input-to-present waits on
C; CI is green with the docs lint through the catalog commits, and the
sheet kind's live test took three commits to pass on Linux and macOS.

Verification: at the async-view head the native library suite runs 111 tests (two
ignored timing probes) and the Dart suite 126, including the live-window,
list, secondary-window, sliced-dataset and released-copy suites and the tab,
radio, menu, theme, chart and tooltip suites merged from `main`, on the debug
library, plus the repository's full check gate. Earlier counts in this
document and in commit messages are the totals at those revisions. The gate
now ends with `tool/docs_check.dart`, which fails when this sentence's counts
differ from the Windows full gate it just ran, when the README's node-kind
count or the Dart node classes differ from the native `Node` enum, when a
node class is missing from the SDK reference, or when the README overview
calls a publication a whole description.
The branch is pushed; the Windows, Linux and macOS SDK checks and the
accessibility probes pass on it, and the Linux and macOS window jobs run the
live-window suite that holds the secondary-window and patch tests.
