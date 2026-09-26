# Startup and memory baselines

Source/artifact baseline: `e9c0c27`. Dart 3.13.4, locked Rust/GPUI dependencies.
Normal release libraries and separate release libraries with `allocation-profile`
were built before collection. Each capture directory records hashes, tool versions,
environment and full failed/successful command output. No failed baseline case
was discarded. Windows: 78 normal cases plus 26 allocation-profile cases passed.
Linux: 90 normal plus 30 allocation-profile cases passed in the
[hosted measurement job](https://github.com/AmeinEskinder/gpuidart/actions/runs/36250180296/job/108426624651).
macOS: 78 normal plus 26 allocation-profile cases passed in the same workflow.
The [dedicated companion analysis](macos-companion.md) separates process roles,
initial transport, memory controls and remaining attribution limits.

## Interpretation

Three fresh-process repetitions per normal case, one allocation-profile pass.
JIT includes `dart run`. Filesystem and driver caches are not purged. Modes, sizes
and controls rotate/reverse; this is not a randomized population study. All
normal host cases enable tracing except the explicit plain AOT controls.
Hardware differs between platforms. Linux uses hosted Xvfb/Mesa software rendering.
These measurements cannot rank operating systems or isolate Dart VM overhead.

CPU content paint means the view completed GPUI's element paint method. It does
not mean GPU submission or visible presentation. Initial spans overlap: decode
is inside FFI; a first paint can occur inside window creation. Do not add their
medians. The driver-to-Dart-main interval includes launch/loader/runtime work,
not a standalone VM boot measurement.

## Windows normal release

Windows 11 Pro 26200, i7-11850H, approximately 32 GiB RAM; display and driver
enumeration in `windows-e9c0c27/windows-environment.json`. AOT medians below:

| Rows | Launch to first CPU content paint, ms | Encode/copy, ms | Native decode, ms | Working set, MiB | Private commit, MiB |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 234.12 | 0.05 | 0.08 | 75.87 | 94.57 |
| 1,000 | 203.88 | 0.41 | 0.30 | 78.47 | 96.23 |
| 10,000 | 251.02 | 2.84 | 2.06 | 83.90 | 103.05 |
| 100,000 | 287.65 | 31.98 | 22.93 | 129.09 | 153.21 |

Memory is the median of three settled observations per process, then the median
across repetitions. The zero-row host has no table, so differences from it include
the fixed table cost. At 100k, the encode span contains JSON (~24.74 ms), UTF-8
(~5.88 ms), and FFI allocation/copy (~1.35 ms); semantic validation is ~0.26 ms.
JIT 100k launch-to-first-CPU-paint is ~1,276.61 ms, of which driver-to-first-Dart
marker is ~882.03 ms. These are candidates for further investigation, not evidence
of a responsiveness advantage.

At 100k, median lifetime peak working set is 133.03 MiB versus settled 129.09 MiB;
peak commit and settled private commit are both approximately 153.21 MiB. Neither
difference measures all temporary allocations or proves that the Dart heap ran GC.

The separate allocation-profile AOT 100k run reports 23,041,141 live requested
Rust bytes, 23,451,891 peak requested bytes, 30,172,115 cumulative requested bytes,
and 310,002 successful requests. Zero rows reports 7,265,182 live bytes. These
exclude Dart, allocator overhead, external malloc and GPU allocations. The
profiled timings are not used in the normal table.

## Linux direct/companion control

The same Linux artifact supports both launch models. AOT medians:

| Rows / model | Launch to first CPU content paint, ms | App RSS / PSS, MiB | UI RSS / PSS, MiB |
| --- | ---: | ---: | ---: |
| 0 / direct | 137.58 | 178.60 / 156.25 | Same PID |
| 100k / direct | 234.28 | 235.37 / 212.94 | Same PID |
| 0 / companion | 144.21 | 15.37 / 10.28 | 173.10 / 148.05 |
| 100k / companion | 271.51 | 68.49 / 63.34 | 197.34 / 172.31 |

At 100k, companion initial re-encoding is ~4.01 ms and child decoding ~20.84 ms.
These are observed Linux transport-path costs. Other differences include process
launch, queues, copies, GC/allocator behavior and rendering initialization. They
do not quantify a macOS shared-process alternative. RSS includes shared pages;
the raw role entries for a direct host are two names for one process.

## Reproduction and remaining work

See `tool/performance/README.md`. `summarize_baselines.dart` reproduces the checked-in
summaries from each raw capture directory. Per-run values and ranges are retained;
the small tables above do not replace them. Build logs for local Windows artifacts
are in `../instrumentation/release-build` and `../instrumentation/profile-build`.

All three platform baselines are recorded. The macOS analysis also identifies
temporary Rust allocation in the application process while it stages the initial
upload. Dart allocation sites and allocator-retained pages have not been separately
attributed; RSS/footprint peaks do not supply that attribution. Still required:
measured optimization decisions and the separate snapshot/subview/patch comparison.
No production protocol change has been made.
