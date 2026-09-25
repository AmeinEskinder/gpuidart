# Comparison status — 2026-09-25

**All 36 Dart/Solid/Shell measurements are complete, with four incomplete attempts retained.** All 3,148 delivered update clicks passed application checks. See the [three-repetition results](dart-js-20260925.md) and [summary retaining all 40 attempts](dart-js-20260925-summary.json). Dart used fewer private bytes than Solid, with a higher idle working set; Shell was lower on both memory measures. Dart's single-cell CPU readings were lower than Solid's, while idle/burst ranges overlapped and every scroll run missed driver slots. Presentation remains unmeasured.

Three repetitions of Rust/Dart workloads previously completed, with a repeated memory premium for the Dart build. See the [Rust/Dart measured results](rust-dart-20260925.md) for CPU, memory, publication, native drawing and reliability observations. That series and its corrected partial follow-up remain separate and have not been extended.

The Rust/Dart series contains 24 foreground runs and 2,101 applied updates from 2,101 injected clicks. It retains one skipped scroll deadline and one extra click at the interval boundary. A follow-up after correcting the cutoff completed 12 runs before two focus interruptions. Diagnostic builds traced another 700 complete input-to-state chains. The original 49-of-50 observation remains unresolved and is retained in the report.

The production snapshot/dataset architecture remains frozen. Native input tracing is opt-in through a diagnostic build feature. The earlier [pilot record](measurements-20260925.md) remains available.

## Completed

- Built a direct Rust + GPUI Kit reference, GPUI Shell/QuickJS fixture, GPUIX/Solid compiled executable and Dart AOT fixture.
- Ran all four workloads with 100,000 records in each implementation: idle, continuous scrolling, one-cell updates and eight-visible-cell bursts. Every delivered update was verified; all scroll fixtures advanced the visible row window.
- Inspected captured native window images. The final fixtures match font size, viewport, column width, row height and physical DPI. Example captures: [Dart burst](final-fixtures-0/dart-burst/offscreen.png), [Rust scroll](final-fixtures-0/rust-scroll/offscreen.png), [Shell scroll](final-fixtures-0/shell-scroll/offscreen.png), [Solid burst](final-fixtures-0/solid-burst/offscreen.png).
- Added a serial runner with input timestamps, scheduling misses, process samples, captures and application verification; a PresentMon capture path; and an analyzer that excludes background runs and leaves unproven response latency null.
- Verified analyzer handling of process/time boundaries, undisplayed frames, the first interval crossing the warmup boundary, and input association versus response latency.
- Saved explicit runtime packages, dependency versions, lockfile hashes and binary hashes in [artifacts.json](artifacts.json).
- Launched each copied package with an unrelated working directory and a Windows-only `PATH`; all four passed ten one-cell updates. Reports are in [packaged](packaged). This verifies local packaging without an SDK on `PATH`, not a clean Windows installation.

The final correctness runs are in [final-fixtures-0](final-fixtures-0). Each workload interval is only two seconds, after warmup. These use posted Windows messages and offscreen native window capture. Some driver deadlines were missed; the application count matches delivered input, rather than an assumed request rate. These are fixture checks, **not comparative performance samples**. Raw process/native timing observations are retained for diagnosis and excluded by the analyzer.

## Findings that changed the fixtures

1. **Shell's component DataTable could open without rendering the dataset.** Its row callback exceeded component bridge limits. The fixture now uses Shell's stock `uniform_list`, preserving 100,000 application records and building visible rows. Host limits and production libraries were not patched. The native DataTable and virtual-list widgets still differ in selection, column controls, scrollbar and some decoration, which remains a comparison qualification. See the pinned [component callback limits](https://github.com/longbridge/gpui-kit/blob/21622a70efd25219d26aa459164878c4da9e39f8/crates/shell/src/engine/quickjs/mod.rs#L9053).
2. **The Dart executable needed explicit DPI awareness.** The benchmark now sets it before opening GPUI. This removes a Windows scaling difference that would otherwise bias render-resolution comparisons. The existing production demo has not been changed by this milestone.
3. **Bun compilation did not embed the native addon.** The Solid package includes its `.node` file beside the executable, and loads that file explicitly. Counting only the executable would understate its runtime payload.
4. **Equal wheel deltas did not produce equal scroll distances.** GPUIX moved 60 logical pixels per -120 event; Kit/Shell moved 78. The runner calibrates GPUIX to -156. In the [calibration matrix](calibration.json), equal delivered event counts produced equal 9,282-pixel displacements in Rust, Dart and Solid, with Shell showing the corresponding row range. Recalibration is required after environment changes.

## Explicit runtime payload

| Implementation | Payload MiB | App directory after first launch MiB |
| --- | ---: | ---: |
| Rust + GPUI Kit | 18.45 | 18.45 |
| GPUI Shell + QuickJS | 58.70 | 59.66 |
| GPUIX + Solid + Bun + native addon | 107.20 | 107.20 |
| GPUI-Dart AOT + DLL | 29.48 | 29.48 |

The payload files are enumerated by [artifacts.json](artifacts.json), including the app-local CRT and the included license file. [App directory measurements](app-directories.json) include Shell's generated type declarations after launch. These are not installer sizes or complete machine-wide post-install footprints; shared OS/driver caches are excluded. The packages still need a clean-machine dependency check. Published GPUIX native build flags are not inferred from the source checkout; its npm version and integrity are pinned.

## Remaining evidence

| Measurement | Current status |
| --- | --- |
| Foreground workload CPU and memory | Rust/Dart series retained separately; Dart/Solid/Shell has 36 completed measurements and 4 incomplete attempts; 25 completed runs met the planned input cadence |
| Native drawing and Dart publication | Recorded separately with original histogram scopes; Solid exports p90/p99 over up to 1,000 draws; Shell has no equivalent native timer |
| Frame/presentation p95 and p99, undisplayed frames | PresentMon ETW capture denied by current Windows permissions; [error log](presentmon-preflight.txt) |
| Input-to-response-present latency | Unmeasured; requires matching the changed-cell frame to its input sequence, in addition to ETW access |
| Missed display deadlines | Unmeasured; driver deadline misses and estimated workload slots must remain separate |
| Startup to usable/displayed UI | Unmeasured; current HWND availability timing is narrower |
| Full installed size and clean-machine launch | Explicit payload recorded; clean Windows machine/VM still needed |
| Human interaction and IME | Not established by this table benchmark |

The foreground runner now activates its own verified window when programmatic focus acquisition fails. It still stops on subsequent focus loss. Correctness failures and interrupted observations remain visible in reliability accounting, with equal-work timing eligibility recorded separately. PresentMon needs an elevated trace-capable session or appropriate Performance Log Users configuration. The [production DPI requirement](../../docs/integration.md#windows-production-dpi-requirement) records the configuration still needed by shipping applications.

The [benchmark guide](../../benchmarks/README.md) contains exact build, capture and analysis commands. A first capture can use one repetition; formal comparisons should use repeated, rotated runs. Review widget parity, display/power settings and response-frame correlation before drawing an architectural conclusion. Publication-stage timings remain separate throughout.
