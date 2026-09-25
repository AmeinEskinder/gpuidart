# Publication tracing

Tracing is opt-in and leaves the snapshot/dataset protocol unchanged. Import
`package:gpuidart/tracing.dart` and supply one `GpuiTrace` per host attempt:

```dart
final trace = GpuiTrace(capacity: 4096);
final host = await GpuiHost.openView(build, datasets: [records], trace: trace);
try {
  await host.editDataset(records, [const CellEdit(0, 1, 'Updated')]);
  await host.rebuild();
} finally {
  await host.close();
  await trace.writeTo('publication.trace.json');
}
```

Load the file in a [Chrome Trace JSON viewer such as Perfetto](https://perfetto.dev/docs/getting-started/other-formats).
Use `trace.measure('static-label', synchronousWork)` to record application preparation.
Labels are recorded verbatim: use static labels without user data. Built-in records
contain stage names, numeric request IDs, timestamps, thread IDs, byte counts and
status codes. They omit control/dataset IDs, text, record values and error messages.

## Clock and correlation

Both runtimes use [Windows QueryPerformanceCounter](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps).
The capture includes its frequency and origin, raw QPC records, and Chrome Trace
events in microseconds. Cross-thread ordering within one QPC tick is ambiguous.
Do not interpret those tiny differences as negative queue or callback delays.

Group records by `(operation, request)` within a capture. Snapshot requests use
their revision; dataset and diagnostic requests use their request IDs. Initial
creation uses `initial/1`. Close and failure markers use request zero. Native
messages rejected before decoding their identity also use zero; do not pair these
with a fabricated application request.

Startup emits both a snapshot-applied event (`snapshot/1`) and ready (`initial/1`).
The initial snapshot has no separate publication request: exclude that initial
acknowledgement when counting replacement snapshots. Later snapshots start at 2.

| Record or interval | Boundary |
| --- | --- |
| `dart.build` | Synchronous `openView` / `rebuild` builder invocation |
| `dart.describe` | Conversion of a view to wire objects; initial conversion includes dataset upload objects |
| `dart.encode` | JSON/UTF-8 encoding, allocation and copying into the FFI buffer |
| `dart.ffi` | Synchronous native call; includes native parsing and queue submission |
| `native.parse` | Decode/validation before queue submission; excludes initial creation |
| `native.enqueue_attempt` → `native.dequeue` | Submission attempt through command pickup, including instrumentation and channel overhead; use only successful submissions |
| `native.dispatch` | UI command handling, including acknowledgement serialization and callback submission; excludes rendering |
| `native.emit` → `dart.receive` | After native event serialization through entry to the Dart callback |
| `dart.decode` | Event decode/validation, plus recording its receive marker |
| `dart.ack` | Validated acknowledgement handled in Dart; native application microseconds are attached when supplied |
| `dart.commit` | Authoritative Dart dataset committed after its acknowledgement |
| `dart.request` → `dart.ack` | Request handling interval, excluding caller preparation and description builder work |

Dataset requests begin after edit validation and conversion to wire objects. Use
an application span to examine that preparation. Stages overlap: native parsing
lies inside the FFI span, and callback delivery can overlap native dispatch.
Adding stage durations or percentiles does not produce end-to-end latency.
Nonzero `native.submit_return` / `dart.ffi` status denotes submission failure;
nonzero `dart.ack` status denotes a rejected operation. Keep failures visible.

Initial tracing includes Dart DLL loading, encoding/create-call time, native run
entry and window-open completion. Initial native parsing precedes trace enable
and is covered only by the Dart create-call span. Window-open completion is not
proof that useful content has been displayed. This trace does not measure external
process launch, VM boot, OS input, layout/drawing, GPU presentation or input-to-present
latency. Inspector RPCs and presentation correlation remain roadmap work.

## Bounds, lifetime and compatibility

Each side retains its first `capacity` complete records (1–8192), then increments
a dropped-record counter. Buffers do not wrap. Duration records are stored when
the span ends; overflow can therefore omit an earlier-starting span. Native reads
copy under a mutex and serialize after releasing it. They neither drain the buffer
nor add application events. Export outside the measured workload where possible.

`toJson()` can inspect a live capture. Live exports may miss in-flight spans.
Await `host.done` or `host.close()` before the final export. Shutdown snapshots the
native buffer before destroying the host. A failed trace read is reported in
metadata and does not turn application shutdown into an error.

Check `metadata.finalized`, `capture_complete`, `dart_dropped`, `native_dropped` and
`native_read_failed` before using a capture. Complete capture means no known record
loss; it does not mean every application request succeeded. Inspect statuses and
unmatched requests too. A shutdown timeout can return before native teardown;
such a capture remains unfinalized until the native runner actually exits.

Tracing uses an optional native extension version 1 (`gd_trace_version`,
`gd_trace_enable`, `gd_trace_read`). The host ABI remains version 1. Untraced hosts
work with older compatible DLLs; tracing explicitly requires the new exports.
Normal hosts do not allocate trace record buffers or call QPC for trace events.
Disabled tracing still adds branches and a small native trace object. Its overhead
has not been isolated. Enabled captures include clock, allocation and mutex costs;
do not compare them directly with historical uninstrumented benchmark timings.

## Reproduce the smoke workload

```powershell
. ./tool/env.ps1
cargo build --locked -p gpuidart
dart run tool/capture_publication_trace.dart build/publication-jit.trace.json
dart compile exe tool/capture_publication_trace.dart -o build/publication-trace.exe
./build/publication-trace.exe build/publication-aot.trace.json target/debug/gpuidart.dll
```

This uploads 100,000 rows, edits one cell 30 times, publishes 30 counter snapshots,
checks the resulting value and revision, and exports after shutdown. Both commands
above use the debug native DLL; the second verifies Dart AOT tracing, not release
performance or clean-machine packaging. The tool retains a partial trace on failure.
