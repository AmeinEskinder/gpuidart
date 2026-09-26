# Reload investigation, 2026-09-25

The original `attempt-023eef4` failure remains unlocalized. This investigation
found and fixed a separate, reproducible diagnostic ordering bug. It does not
establish the cause of the original table comparison failure.

## Observation and cause

Two instrumented runs on the native implementation from `d463696` returned the
`prepare` diagnostic while `watchlist.visible_rows` was still `0..9` and
`scroll_y` was zero. A later inspection showed `25..34` and `-800`, the requested
scroll position. Both runs passed all eleven reload comparisons. Their original
verifier discarded the preparation reply; this investigation saved it.

The pinned GPUI Kit table implements `scroll_to_row` by setting a deferred scroll
request. GPUI consumes it during the uniform list's prepaint. GPUI's frame loop
runs next-frame callbacks before drawing. Our diagnostic scheduled its reply in
such a callback without checking whether a draw had happened, so it could return
the old visible range and scroll offset.

The headless regression `preparation_ack_waits_for_rendered_scroll` reproduces
that ordering directly: request preparation, deliver a frame callback without
drawing, and assert that no acknowledgement has arrived. It failed before the
fix with `A frame callback before drawing must not acknowledge an unapplied scroll`.
See [the retained failure output](regression-before-fix.log).

## Fix and verification

Commit `edffde4` makes preparation use the existing bounded repaint diagnostic
path and wait for a new materialization before replying. The regression also
applies a snapshot while scrolling is pending, then draws and verifies the same
table entity, requested visible range, input text, selection and focus.

The reload verifier now saves the preparation reply, requires row 25 to be
visible before starting, and checks retained state after rendering each reload.
Its existing immediate comparisons remain in place. The default 300 ms delay is
unchanged; the zero-delay probe checks that preparation no longer depends on it.
On failure it saves additional post-render inspection without converting failure
to success. Report paths are selectable so probes do not overwrite candidate evidence.

| Capture | Preparation reply | Reload comparisons |
| --- | --- | --- |
| [Before fix, 300 ms delay](before-fix-default.json) | Row range `0..9`, scroll `0` | 11 passed under the earlier checks |
| [Before fix, no delay](before-fix-no-delay.json) | Row range `0..9`, scroll `0` | 11 passed under the earlier checks |
| [After fix, 300 ms delay, tracing off](after-fix-default.json) | Row range `25..34`, scroll `-800` | 11 passed, immediately and after rendering |
| [After fix, no delay, tracing on](after-fix-no-delay.json) | Row range `25..34`, scroll `-800` | 11 passed, immediately and after rendering |

Each run also rejected invalid Dart source and recovered without restarting the
application or republishing dataset records. The [before](before-fix.trace.json)
and [after](after-fix.trace.json) captures retain correlated publication events.
Both trace exports finalized without reported drops or read failures. Native
dispatch spans cover synchronous handling; deferred diagnostic replies occur
later. These debug-DLL captures do not measure presentation or comparative latency.

`./tool/check.ps1` passed all **12 native tests and 27 Dart tests**, formatting and
analysis with this change. [Verification metadata](verification.json) records the
source and artifact hashes. No new release ZIP or full nine-step acceptance run
was produced for this diagnostic milestone.

Reproduce:

```powershell
./tool/check.ps1
dart run tool/verify_watchlist_reload.dart --report=build/reload-default.json
dart run tool/verify_watchlist_reload.dart --report=build/reload-traced.json --prepare-delay-ms=0 --trace
```

## Remaining uncertainty

The original failure saved neither differing table value. It might have involved
entity identity, visible range, scroll offset, row count or dataset revision.
The new evidence cannot choose among those possibilities. The render-order fix
removes a demonstrated weakness in the diagnostic precondition, but the original
observation remains open. Future failures retain preparation, immediate state,
post-render state and optional request traces.

### Historical source audit, 2026-09-26

The original verifier at `023eef4` required `before.state.tables.watchlist.scroll_y`
to be negative before it changed source and requested reload. The saved failure
occurred later at the whole-table comparison. Therefore a still-zero scroll
offset in that `before` inspection cannot explain this specific failure.
The comparison covered entity ID, visible row range, source row count, dataset
ID, dataset revision and scroll offset. Neither compared object was saved.

The current `bb6a894` release run passed eleven reloads, including comparisons
after rendering. Those values and the earlier passing repetitions cannot recover
the missing original values. Repeating the same successful workload again would
not localize the historical failure, so no additional runtime fix or relaxed
assertion follows from this audit. The observation remains an explicit unresolved
release decision.

### Recovered fixture audit, 2026-09-26

The original `.cache/watchlist-reload-f29d2617` directory still exists. Its
creation time falls within the failed reload check. Its `main.dart` matches the
original source, and `app.dart` differs only by the first heading edit after
normalizing line endings. [The source audit](source-forensics-20260926.json)
records file hashes, timestamps and comparisons.

The directory contains only those two source files. It supplies no runtime
table values or input/foreground trace. The original verifier had already
accepted the changed heading, application state and input-state equality before
the table comparison failed. This narrows the failed stage but does not identify
the differing table field. The issue remains open. Closing it as an accepted
historical exception would require an explicit owner decision and would not
establish a runtime fix.
