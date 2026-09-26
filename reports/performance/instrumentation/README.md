# Startup instrumentation checks

These checks exercise the debug native library on Windows. They are correctness
evidence, not startup or throughput performance results. The measurement work
order is in `docs/performance-milestone.md`.

## Boundaries added

Optional trace extension 2 enables tracing before initial native decode and
validation. Dart separates JSON, UTF-8 and FFI allocation/copy. Runner, companion
initial transport, window creation and first CPU content-paint stages are explicit.
Host ABI 1 and the production snapshot/dataset protocol are unchanged. The Dart
reader retains support for trace extension 1.

The paint wrapper observes completion of the Dart view's element paint. It does
not observe GPU submission, presentation, or input-to-present latency. GPUI can
paint during `open_window`; stage intervals may overlap.

## Attempts retained

| Attempt | Result and disposition |
| --- | --- |
| Initial shell attempt (session output only) | PowerShell treated ordinary Cargo stderr as a terminating error under `ErrorActionPreference=Stop`. No usable log was retained. Replaced the logging pipeline with `tool/performance/run_logged.dart`, which retains stdout, stderr and exit status independently. |
| `paint-test-first/` | Regression assertion expected no paint after `open_window`; GPUI's test helper had already painted. Moved the pre-paint assertion inside window construction. |
| `native-tests/` | All 42 native tests passed, including actual content paint, exactly one first-paint marker, and traced-create FFI validation. |
| `native-build/` | Debug library build passed. |
| `live-trace/` | Both live tests failed because the Dart trace reader's allowlist rejected the new stage names. No application-update failure was observed. |
| `live-trace-reader-fixed/` | Both live tests passed after updating the trace reader. Includes stage/byte correlation, content privacy, bounded overflow and shutdown. |

`dart analyze` and the headless Dart tests also passed. At `61c61b9`, hosted
[macOS](https://github.com/AmeinEskinder/gpuidart/actions/runs/36249486205),
[Linux](https://github.com/AmeinEskinder/gpuidart/actions/runs/36249486233),
[Windows](https://github.com/AmeinEskinder/gpuidart/actions/runs/36249486183) and
[Unix lifecycle](https://github.com/AmeinEskinder/gpuidart/actions/runs/36249486184)
checks passed. macOS exercises the new companion stage assertions.

## Baseline harness checks

`runtime-metrics/` passes the Windows native OS-counter regression.
`native-memory-build/` builds that debug DLL. `baseline-smoke/` runs fresh AOT
processes with zero and 100k rows against it. Both passed; the two raw captures,
artifact hashes and driver timestamps are under `baseline-smoke/captures/`.
They verify measurement collection, not release performance. Source metadata
correctly records the uncommitted harness/native-metrics changes in this attempt.
The driver reports first content paint from launch and preserves incomplete
captures/failures. Plain builds and allocation-profile builds will be measured
separately. Release baselines and the step-6 comparison are still pending.

`release-build/` and `profile-build/` retain optimized normal/profile build logs.
`profile-smoke/` passes zero/100k AOT fixtures with the separate profiled library.
Raw captures show nonzero Rust allocator requests and a live/peak distinction;
these profiled timings are excluded from normal release timing comparisons.
