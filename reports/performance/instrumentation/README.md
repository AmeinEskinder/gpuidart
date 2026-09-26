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
| `paint-test-first-attempt.log` | PowerShell treated ordinary Cargo stderr as a terminating error under `ErrorActionPreference=Stop`. Replaced the logging pipeline with `tool/performance/run_logged.dart`, which retains stdout, stderr and exit status independently. |
| `paint-test-first/` | Regression assertion expected no paint after `open_window`; GPUI's test helper had already painted. Moved the pre-paint assertion inside window construction. |
| `native-tests/` | All 42 native tests passed, including actual content paint, exactly one first-paint marker, and traced-create FFI validation. |
| `native-build/` | Debug library build passed. |
| `live-trace/` | Both live tests failed because the Dart trace reader's allowlist rejected the new stage names. No application-update failure was observed. |
| `live-trace-reader-fixed/` | Both live tests passed after updating the trace reader. Includes stage/byte correlation, content privacy, bounded overflow and shutdown. |

`dart analyze` also passed. Companion stage checks run in macOS CI (and in Linux
companion mode); they have not been locally executed in this Windows attempt.
Baseline data, macOS overhead controls and the step-6 comparison are still pending.
