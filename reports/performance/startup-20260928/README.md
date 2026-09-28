# Startup split and the font enumeration patch (2026-09-28)

Where the time before the first window goes on Windows, and the one change it
justified: the vendored `gpui-pre-windows` 0.3.7 no longer asks DirectWrite to
check for font changes when it fetches the system font collection at startup
([font-collection.patch](../../../native/vendor/font-collection.patch)).

## Method

Three trace points were added to the native run entry (`native.app_built`,
`native.app_callback`, `native.kit_init`; see [tracing](../../../docs/tracing.md))
so the interval between `native.run` and `native.window_create` splits into
GPUI application construction, run-loop start and GPUI Kit initialization.
`run_baselines.dart` smoke mode (AOT host, 0 and 100,000 rows, traced, three
repetitions) ran against `target/release` built from the same tree before and
after the patch, minutes apart on the same machine; the captures are in
[before](before) and [after](after). The [probe test](../../../native/src/startup_probe_tests.rs)
(`cargo test -p gpuidart --lib startup_platform_costs -- --ignored --nocapture`)
times the raw Windows calls GPUI makes in a fresh process; its three runs are in
[probe.jsonl](probe.jsonl). The timed calls are operating-system work, so the
debug test binary is adequate.

## Where the time went (before)

Zero rows, milliseconds from the Dart build call, one representative run:

| Stage | At |
| --- | ---: |
| Native library loaded | 5 |
| `gd_create` returned, runner spawned, `native.run` | 6 |
| GPUI application constructed (`native.app_built`) | 134 |
| Launch callback entered | 134 |
| GPUI Kit initialized | 137 |
| Window created and first content paint | 175 |
| Host ready | 175 |

Application construction was 125 to 147 ms of a 174 to 201 ms host-ready.
The probe attributes it: the first `GetSystemFontCollection` call with
`checkForUpdates = true` took 85 ms and 163 ms in two fresh processes, and
1.1 ms with `false`; DXGI factory and adapter 13 to 23 ms; D3D11 device
creation 30 to 45 ms; a second application constructed in the same process,
with the collection already cached, 34 to 53 ms.

## After the patch

Medians of three runs with [min, max]:

| Case | Metric | Before | After |
| --- | --- | ---: | ---: |
| AOT host, 0 rows | Host ready, ms | 175.2 [173.6, 201.4] | 118.5 [95.5, 136.8] |
| AOT host, 0 rows | Application construction, ms | 128.0 [125.5, 146.6] | 57.1 [47.0, 69.6] |
| AOT host, 0 rows | Window create to first paint, ms | 38.5 [37.0, 38.9] | 45.1 [39.7, 53.6] |
| AOT host, 100,000 rows | Host ready, ms | 232.0 [224.3, 277.8] | 139.5 [132.4, 239.1] |
| AOT host, 100,000 rows | Application construction, ms | 140.1 [131.9, 166.9] | 46.9 [44.1, 73.6] |
| AOT host, 100,000 rows | Window create to first paint, ms | 41.3 [38.7, 46.3] | 42.6 [41.3, 80.8] |

The one 100,000-row run at 239 ms after the patch spent 81 ms in window
creation; it is retained. Kit initialization stays at 3 to 4 ms.

## What remains

Application construction is now the D3D11 device and DXGI factory (about 45
to 60 ms, driver work) plus the DirectWrite factory, GPU state and OLE
initialization. Window creation and the first paint take about 40 ms.
Before `native.run`, the Dart side spends 6 ms at zero rows and 45 to 60 ms
at 100,000 rows building, describing and encoding the records and having
native decode and validate them; starting the platform construction before
that work, rather than after `gd_create`, is the next structural option and
would overlap up to that much. Memory at zero rows (private commit about 99
MB) is not touched by this change.

## Memory at zero rows

The probe's fourth run also reads the test process's private commit after
each step: 2.6 MB at the start, 6.4 MB after the DirectWrite factory and both
font collections, 41.5 MB after the DXGI factory and D3D11 device (35 MB of
driver allocations), and 74.1 MB with a GPUI application constructed on top,
which creates its own device again (about 33 MB more). In the host process the
capture reports 13 MB of Dart VM resident memory before the library loads and
94 MB private commit once the window is ready, so roughly a third of the
zero-row footprint is the graphics driver's device state, an eighth the Dart
runtime, and the remainder the window's swap chain and composition surfaces,
glyph atlas, GPUI Kit globals and the Rust heap. No SDK-level change reaches
the driver's share; the font collection patch does not change memory.

These figures come from one machine within one session and are not comparable
with the [September baselines](../baselines/README.md), whose absolute startup
figures differ by day.
