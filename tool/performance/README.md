# Performance measurements

Run from the repository root. `run_logged.dart` preserves stdout, stderr and
exit status in a new directory. `run_baselines.dart` refuses existing output
directories and records every completed or failed case. It hashes the supplied
native library, companion launcher and generated AOT executable. Build flags
must be retained in a separate command log; a path named `release` is not proof
of its compilation settings.

```powershell
dart run tool/performance/run_logged.dart build/performance-build cargo build --locked --release -p gpuidart
dart run tool/record_platform_environment.dart build/performance-environment.json
dart run tool/performance/run_baselines.dart build/performance-windows target/release 3
```

Unix also requires `-p gpuidart-launcher`. `.github/workflows/performance.yml`
runs the same tools on hosted macOS and Linux/X11. These are machine-specific
baselines; hosted Linux uses Mesa software rendering.

To capture a snapshot gate for a baseline checkout and the current checkout,
using each checkout's SDK and release library:

```sh
dart run tool/performance/run_update_gate.dart --baseline ../baseline --output build/update-gate
```

`--target-dir` selects a Cargo build directory. Each side's binaries are copied
before building the next side. `--sides trunk,head` selects the sides to run;
existing series are retained and cannot be overwritten.

## Cases

- Fresh JIT and AOT processes: zero, 1k, 10k and 100k rows.
- Data-only control: authoritative Dart records, no native library load.
- Library-only control: same Dart records plus library load/runtime probe, no UI.
- Host: same records, fixed 960x640 logical window, two-column virtualized table.
- Separate plain AOT host runs at zero/100k to observe trace overhead.
- Linux additionally runs the companion path at every size in AOT. This measures
  Linux's process-model difference; it is not a substitute for macOS controls.

Cases rotate/reverse between repetitions. Within each process, three samples
follow 700 ms intervals. No forced GC; these are settled observations, not proof
of eventual minimum memory. `ProcessInfo` RSS is available before library load.
Native runtime metadata reports each role's OS metrics and lifetime peaks. A
shared-process host has one PID; never double-count its two roles.
Fresh process does not mean a cold filesystem or driver cache; the suite does
not purge machine caches between cases.

The driver timestamps before process start, including launcher/`dart run` costs.
The first Dart marker follows construction of its OS clock; clock initialization
has a separate stopwatch interval. Pre-main VM/loader work remains aggregated.
First content paint means CPU scene construction for the view, not presentation.
Span nesting and overlap prohibit summing all durations.

Mac controls identify observed application-process costs (including its loaded
library), UI-process costs and initial serialization/transport stages. Differences
between controls include their changed work and GC behavior. They do not isolate
a hypothetical shared-process AppKit implementation or exact Dart VM overhead.
Twenty `inspect` round trips include diagnostic serialization and scheduling.

## Allocation profile

Build separately with `cargo build --release --locked -p gpuidart --features
allocation-profile`. Preserve the normal artifact first and run a separate
series. The runtime probe then reports Rust global allocator requested live bytes,
high water, cumulative requested bytes and successful allocation requests.
Reallocation counts its new requested size. Concurrent counter reads are not an
atomic heap snapshot. Counts exclude Dart allocations, allocator metadata,
external malloc users and GPU memory. The allocator affects execution time;
do not use that build for the normal timing baseline. Peak-minus-settled is a
high-water difference, not a count of all temporary allocations.

OS counters retain their meanings: Windows working set/private commit and their
respective peaks ([Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex));
Linux RSS/PSS from `smaps_rollup` and peak RSS from
[`getrusage`](https://man7.org/linux/man-pages/man2/getrusage.2.html);
macOS resident size/physical footprint and lifetime maximum physical footprint
from [`RUSAGE_INFO_V4`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h).
RSS sums across processes include shared pages; none is a universal memory metric.

## Snapshot strategy experiment

Build the separate executable with `cargo build --locked --release -p gpuidart
--features snapshot-experiment --bin gpuidart-snapshot-experiment`. Build the
launcher too on Unix. Preserve the normal executable before building with
`snapshot-experiment,allocation-profile` for a separate profile series.

```powershell
dart run tool/performance/run_strategies.dart build/strategies-normal target/release/gpuidart-snapshot-experiment.exe target/debug/gpuidart-launcher.exe 3
dart run tool/performance/summarize_strategies.dart build/strategies-normal build/strategies-normal-analysis.json
```

Use unsuffixed executable names on Unix. This is common framed process transport,
not production FFI. The [experiment contract and results](../../reports/performance/strategies/README.md)
specify fixed geometry, supported mutations, state-ownership limits and timing
boundaries. `.github/workflows/snapshot-experiment.yml` reproduces all platforms.
The runner records expected-case counts, and the summarizer rejects partial runs.

## Direct UTF-8 encoding comparison

`run_encoding.dart NEW_DIRECTORY` builds the isolated encoder fixture, checks
byte equivalence and runs three repetitions in JIT/AOT. Reduce its results with
`summarize_encoding.dart CAPTURE_DIRECTORY NEW_OUTPUT_JSON`.

`run_baselines.dart NEW_DIRECTORY NATIVE_DIRECTORY 3 encoding` compares actual
AOT hosts at zero and 100k records, compiling both the default fused encoder and
the internal `--define=gpuidart.legacy_json=true` control. Both use the exact same
native library. Select `measurement=encoding` when dispatching `performance.yml`
to repeat this on Windows/macOS/Linux. See the [keep decision](../../reports/performance/encoding/host-results.md).
