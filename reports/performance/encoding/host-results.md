# Host encoding comparison

Candidate source `2fb9ef8`. [Hosted run 36261368160](https://github.com/AmeinEskinder/gpuidart/actions/runs/36261368160) passed on all three platforms. Each platform ran twelve fresh AOT host cases: zero/100k records x legacy/fused x three repetitions, with rotated/reversed order. Both executables load the same normal release library. Data, window, instrumentation and completion checks match. The internal `gpuidart.legacy_json=true` compile-time control selects the former encoding path.

## Timing

Median milliseconds; encoding includes UTF-8 generation and FFI allocation/copy. First content paint is CPU scene construction, not presentation. Its change includes other startup variation and must not all be attributed to encoding.

| Platform | Rows | Encode/copy legacy to fused | Launch to CPU content paint legacy to fused |
| --- | ---: | ---: | ---: |
| windows | 0 | 0.038 to 0.034 | 80.475 to 80.481 |
| windows | 100,000 | 39.050 to 24.823 | 166.309 to 151.943 |
| linux | 0 | 0.041 to 0.039 | 124.993 to 123.261 |
| linux | 100,000 | 33.143 to 24.234 | 207.358 to 201.323 |
| macos | 0 | 0.036 to 0.038 | 314.112 to 300.014 |
| macos | 100,000 | 32.380 to 21.936 | 393.551 to 387.530 |

## Application-process memory at 100k

MiB. Windows/Linux share the application and UI process; macOS roles are separate and are not summed. Values are medians of three settled samples, then medians across runs. OS lifetime peaks are independent metrics.

| Platform / metric | Legacy | Fused |
| --- | ---: | ---: |
| windows / memory_bytes.working_set | 101.21 | 96.76 |
| windows / memory_bytes.private_commit | 107.10 | 98.04 |
| windows / memory_peak_bytes.working_set | 101.21 | 96.76 |
| windows / memory_peak_bytes.commit | 107.10 | 98.04 |
| linux / memory_bytes.Rss | 235.82 | 231.02 |
| linux / memory_bytes.Pss | 213.36 | 208.58 |
| linux / memory_peak_bytes.rss | 235.25 | 230.40 |
| macos / memory_bytes.resident_size | 72.69 | 68.39 |
| macos / memory_bytes.physical_footprint | 41.16 | 36.94 |
| macos / memory_peak_bytes.physical_footprint | 56.72 | 52.60 |

The macOS UI process still performs its separate initial parse/transport/rendering work; its raw counters are retained. This optimization changes Dart encoding, not the companion architecture. Memory from repeated encoding-only loops remains mixed, as documented in the main report.

## Process CPU through the after-ready probe

Total user + system CPU milliseconds, summed per process/sample before taking medians across runs. This interval includes all startup plus the readiness/dataset verification work. It does not isolate encoder CPU or input responsiveness. Windows accounting is relatively coarse; raw samples remain available.

| Platform | Process role | Rows | Legacy | Fused |
| --- | --- | ---: | ---: | ---: |
| windows | application/UI | 0 | 250.00 | 171.88 |
| windows | application/UI | 100,000 | 312.50 | 296.88 |
| linux | application/UI | 0 | 212.52 | 188.93 |
| linux | application/UI | 100,000 | 377.97 | 373.97 |
| macos | application | 0 | 18.33 | 28.15 |
| macos | application | 100,000 | 111.59 | 106.47 |
| macos | ui | 0 | 206.16 | 175.95 |
| macos | ui | 100,000 | 204.43 | 190.32 |

## Windows physical-machine follow-up

The twelve local cases in `host-windows-local/` all passed, using the preserved normal `e9c0c27` DLL for both executables. The 100k encode/copy medians were 55.19 to 26.64 ms; first CPU content paint was 411.71 to 339.28 ms. This host was running other applications, and zero-row fused readiness included a 769.72 ms sample. These observations stay separate from the hosted series and do not establish a general startup speedup.

## Payload and decision

Windows Watchlist AOT executables were compiled from the same source with the production packaging define, then embedded with the same DPI manifest. Legacy: 6,715,392 bytes; fused: 6,757,376 bytes, an increase of 41,984 bytes (41 KiB). Build logs and hashes are in `watchlist-size/`. This is the executable delta, not total installed size; native libraries and assets are unchanged by the Dart encoder choice.

**Keep direct UTF-8 encoding.** It improves the measured large-payload encoding stage on all three platforms with byte-equivalent output and passing real-host data checks, while the 100k startup fixture uses less application memory. Accept the small executable increase and retain the repeated-encoding peak-memory caveat. No claim of lower memory for every workload or better presentation latency is made.

The old path is retained only behind an internal compile-time measurement control so this comparison remains reproducible; default builds select direct UTF-8 encoding. No failed production optimization was reverted in this milestone. General patches/subviews remain isolated experiments, with their separate non-adoption decision in the strategy report.
