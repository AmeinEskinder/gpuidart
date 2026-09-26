# Feature stack verification — 2026-09-26

Source: `1eafed0` (watchlist migration), covering roadmap steps 3–4 from
[the feature-stack design](../../docs/feature-stack.md): typed styles
(`e957d44`), scoped actions (`135d300`), stable record IDs and dataset views
(`e3238ca`), declarative cell formatting (`119217e`), and the watchlist
migration that exercises all four against a real window (`1eafed0`).
The host ABI remains version 1; every addition is an optional field.

## Completed checks

- 41 native tests passed, including style/view/action/format validation, a
  headless view suite (sort order, selection by record ID through sort and
  filter, disappearance rule, scroll anchor, recompute triggers) and the
  allocation/viewport scaling probes.
- 41 Dart tests passed, including the live-window host suite with action and
  view round-trips. Dart analysis, Rust formatting and Dart formatting passed.
- The JIT and AOT 100,000-row trace smoke workloads were re-run on this code:
  each uploaded 100,000 rows, completed 30 cell edits and 30 replacement
  snapshots, and exported after shutdown. Both captures contain 848 records
  with no reported loss and no failed acknowledgements; all 61 requests have
  one record per checked stage. Record counts and per-operation byte counts
  are identical to the [previous tracing milestone](../tracing/README.md) —
  the smoke workload does not use the new features, so nothing changed there.
- [Reload at 100,000 records](reload-100k.json): the watchlist reload check
  now selects a record natively (`select_row` diagnostic), filters the view
  (100,000 → 34,390 rows under the prepare filter) and confirms across 11
  code reloads that the selected record (`BRK0025`), view state, scroll and
  dataset revision are unchanged and no unchanged records are republished
  (data-byte metrics equal before/after). The 1,000-record check still passes.
- [Live watchlist UI verification](../../tool/verify_watchlist_ui.dart)
  against the real window: view filtering, record selection preserved through
  a price sort (row 0 → row 124), formatted cells via the `formatted_cell`
  diagnostic, and both scoped actions (`ctrl+f`, `ctrl+enter`) via real key
  injection.

## Measured numbers (debug build, this machine)

- View recompute (filter + sort) at 100,000 records: ≈43 ms
  (`view_recompute_at_100k_records_is_measured`).
- Cell formatter: ≈1.7 µs per cell (`cell_formatter_cost_is_measured_at_100k_cells`).
- Formatted rendering keeps construction constant across dataset sizes:

  | records | rows constructed | cells constructed | allocation calls | allocated bytes |
  | --- | --- | --- | --- | --- |
  | 100 | 110 | 380 | 28,261 | 12,285,796 |
  | 10,000 | 110 | 380 | 28,260 | 12,285,540 |
  | 100,000 | 110 | 380 | 28,261 | 12,547,684 |

[Verification metadata](verification.json) records source, runtime, artifact
hashes, capture bounds and per-request stage completeness. Machine details are
in [reports/environment.json](../environment.json). All measurements use the
**debug** native DLL; they are not release performance.

## Notable findings while implementing

1. Serde's internally tagged `Change` buffers content, which cannot coerce
   JSON object keys to integers; dataset format maps parsed at upload but not
   through `gd_dataset`. `DatasetFormat` now parses string keys explicitly,
   with a regression test through `Update::parse`. Found by the live Dart
   round-trip.
2. Posted Windows key messages never enter the target thread's keyboard
   state, so the live probe's modifier combos needed `AttachThreadInput` +
   `SetKeyboardState` rather than `PostMessage` or foreground stealing.
3. gpui-kit renders filler rows past a short table's data through
   `render_tr`; row elements are keyed by source record, with a separate
   filler-row ID namespace.
4. Typing characters that momentarily over-narrow a view filter clears the
   selection per the disappearance rule; the verifier refines searches with
   backspaces (which only widen) instead.

## Known limitations

- Action contexts resolve the focused input or table; a focused button
  resolves as no focused node (gpui-kit does not expose its focus handle).
- Watchlist search filters the symbol column only: the view op set has no OR
  across columns. `contains` is case-sensitive.
- Modifiers in key bindings are literal (`ctrl` is control, `meta` is the
  platform meta key); there is no platform-primary alias. On Windows, AltGr
  produces ctrl+alt, so ctrl+alt bindings can fire while typing national
  characters — part of the open IME verification gate.
- Linux verification runs under Xvfb with scale factor 1; HiDPI, Wayland and
  physical-display behavior are unverified. These checks ran on Windows.
- Debug-build measurements are not release performance.

## Non-claims

- No presentation or input-to-present latency was measured; acknowledgement
  is not a display fence.
- This is not a performance comparison against other runtimes, and nothing
  here selects an overdraw configuration or a patch protocol. Roadmap step 6
  (node patches) remains gated on a demonstrated snapshot-heavy workload.
