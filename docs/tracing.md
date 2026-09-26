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

Both runtimes use the same OS clock. Windows uses
[QueryPerformanceCounter](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps),
Linux uses `CLOCK_MONOTONIC` nanoseconds, and macOS uses raw
`mach_absolute_time` ticks. Captures record frequency, origin, epoch, suspend
behavior and available resolution. Chrome Trace events convert those ticks to
microseconds. The one-tick cross-thread ordering allowance applies only to QPC;
Unix ordering uncertainty has not been independently calibrated.

Records carry process IDs. On macOS, native parsing/enqueue occurs in the Dart
process and dispatch/emit occurs in the companion. Enqueue-to-dequeue includes
socket transport and both bounded queues; emit-to-receive includes return
transport. These are complete integration intervals, not isolated FFI costs.

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
| `dart.json`, `dart.utf8`, `dart.ffi_copy` | Nested encoding stages: JSON string, UTF-8 bytes, then FFI allocation/copy |
| `native.initial_decode`, `native.initial_validate` | Initial JSON decode and semantic validation, inside the create call (extension 2) |
| `dart.runner_spawn`, `native.runner_entry`, `native.run` | Isolate spawn interval, native runner entry, UI application entry |
| `dart.companion_start` | Socket preparation and child process launch, when used |
| `native.companion_encode`, `native.companion_write` | Initial Rust transport JSON serialization and framed socket write |
| `native.companion_receive`, `native.companion_decode` | Child initial receive/wait and JSON decoding; receive can overlap parent write |
| `native.window_create` | GPUI `open_window` call; may include the first paint |
| `native.content_paint`, `native.first_content_paint` | Dart view's CPU element paint interval and first successful completion; excludes GPU submission/presentation |
| `dart.ffi` | Synchronous native call; includes native parsing and queue submission |
| `native.parse` | Decode/validation before queue submission; excludes initial creation |
| `native.enqueue_attempt` → `native.dequeue` | Submission attempt through command pickup, including instrumentation and channel overhead; use only successful submissions |
| `native.dispatch` | Synchronous UI command handling; immediate replies include acknowledgement serialization and callback submission. Deferred diagnostics reply later. Excludes rendering |
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

Initial tracing includes native library loading, encoding/create-call time and,
with extension 2, initial decode/validation and first CPU content paint. The paint
wrapper delegates layout unchanged and records after the content element paints;
other root elements and GPU submission can follow. Window creation and content
paint can overlap. Neither marker proves displayed pixels. External process
launch needs a driver using the same OS clock; VM initialization before Dart main,
OS input, full-window layout, GPU presentation and input-to-present latency remain
outside these built-in spans.

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

The macOS companion sends a final trace before AppKit terminates it. Until that
arrives, `remote_complete` is false. Each native process has a bounded buffer;
the merged native export is capped at the configured capacity and counts dropped
records. Host finalization also waits for the child process to exit. The extra
process and buffers must be included when measuring the macOS integration.

Check `metadata.finalized`, `capture_complete`, `dart_dropped`, `native_dropped` and
`native_read_failed` before using a capture. Complete capture means no known record
loss; it does not mean every application request succeeded. Inspect statuses and
unmatched requests too. A shutdown timeout can return before native teardown;
such a capture remains unfinalized until the native runner actually exits.

Tracing uses an optional native extension version 2 (`gd_trace_version`,
`gd_trace_enable`, `gd_trace_read`, `gd_create_traced`). Dart also accepts version 1;
its initial decode/validation precedes trace enable and lacks the new native
startup/paint spans. The host ABI remains version 1. Untraced hosts
work with older compatible libraries on Windows/Linux; macOS additionally
requires companion lifecycle extension version 2. Tracing requires its own
exports. Normal hosts do not allocate trace record buffers. Companion startup
reads three timestamps before it learns whether tracing is enabled; untraced
shared-process hosts do not read clocks for trace events.
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
