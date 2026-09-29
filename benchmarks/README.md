# Implementation comparison

The production GPUI-Dart adapter is unchanged. These fixtures use its existing whole-view snapshots and dataset API.

## Build

From the repository root, with the existing Rust/MSVC, Dart and Bun toolchains, plus the Flutter SDK and Visual Studio 2022 Build Tools with the C++ workload for the Flutter fixture (`-NoFlutter` skips it):

```powershell
./benchmarks/build.ps1
./benchmarks/install-presentmon.ps1
```

The native reference uses Rust state and GPUI Kit controls directly. Shell uses QuickJS, its stock component host for buttons, and `uniform_list` for table rows. Solid uses the published `@gpuix/solid` and native addon, both 0.10.0. Dart is compiled to an AOT executable and opens its window before uploading the records (`deferDatasets`), the SDK's documented path for large datasets; series captured before 2026-09-29 used the fixture without that flag, so their window-availability figures include the upload. Flutter is a stock Windows desktop application: a `ListView.builder` with a fixed item extent over the same records, Material tonal buttons with the ink ripple disabled (with it on, every click workload animates at the display rate, which the Kit fixtures' buttons do not do), `setState` on the page for the update workloads, and a release build with the engine DLL and AOT data directory beside the executable. Pins, build descriptions, lockfile hashes and payload hashes are in [artifacts.json](../reports/comparison/artifacts.json).

The Shell component `DataTable` is unsuitable for this fixture at the pinned revision: its data callback exceeds the host's 4,096-value/1,024-object-key limits. Its default columns are also 100 pixels, with no exposed width setter. The virtual-list fixture avoids modifying those host limits. It is a different widget implementation from GPUI Kit's DataTable; results must retain that qualification. Shell's `check` command also panics on this virtual-list fixture because it materializes outside a rendering view. The live window checks pass.

## Verify the fixtures

```powershell
./benchmarks/suite.ps1 -RunId smoke -Repetitions 1 -Seconds 2 -BackgroundSmoke
./benchmarks/analyze.ps1 -Directory reports/comparison/smoke-0
./benchmarks/test-analysis.ps1
```

Background checks post window messages to the window that owns the pixels under the target point (Flutter hosts its content in a child view; the GPUI fixtures have none). They verify edits, scrolling and the native window's rendered image through `PrintWindow`. They do not measure physical input or display presentation. The analyzer excludes them from performance results. Flutter's embedder reads the wheel position from the real cursor rather than from the message, so its background scroll check cannot pass; its scroll workload is verified by the foreground runner only.

Each fixture has 100,000 identical records (`-Rows` changes the count for the idle and view workloads only; both fixtures read it from `GPUIDART_BENCH_ROWS`), three 200-pixel columns, 32-pixel rows, a 320-pixel table viewport, 16-pixel text and an 860 × 650 logical-pixel client area. Captures on this machine are 1075 × 812 physical pixels at 125% scaling. The Dart benchmark selects per-monitor DPI awareness before starting GPUI; without that startup setting, Windows bitmap scaling makes its render resolution different. This setup is confined to the benchmark entry point. All fixtures construct only rows near the viewport; Solid retains a window of 32 row components, and Flutter builds rows inside its cache extent (the viewport plus 250 logical pixels on each side) and rebuilds the visible ones on every `setState`. The Flutter runner declares per-monitor DPI awareness in its manifest. GPUI Kit adds selection, column controls and a scrollbar that the two list fixtures do not reproduce. Header separators and rounding also differ slightly.

The workloads run in fresh processes after a three-second warmup:

| Workload | Input |
| --- | --- |
| Idle | No updates |
| Scroll | 60 wheel events/second, calibrated to 78 logical pixels/event |
| Cell | 5 clicks/second, each changes row 0's price |
| Burst | 30 clicks/second, each changes prices in visible rows 0–7 |
| View | 1 click/second, each moves the table to the next of four stages: a descending sort on the price, the sort with a filter keeping prices above 5,100, both with a grouping by sector (a header row per group with the count, average and maximum price), and the plain records again; runs at any row count (`-Rows 1000000`) |

In the view workload the fixtures read `GPUIDART_BENCH_WORKLOAD=view`, add a fourth 200-pixel `Sector` column with twelve values to group by, and turn the first button into the view cycle, and the runner keeps the pointer moving over the rows at 60 Hz between the clicks (`hover_moves` in `run.json`), which both fixtures repaint for, so a gap between frames during a view change is a stall rather than idleness. The Dart fixture republishes the table with the next view and measures the click handler through the rebuild acknowledgement (`apply_us`, sent before the view index computes off the frame thread) and on to the `table_view` event that reports the index in place (`settle_us`); it marks native's frame counter in the handler and reports the frames native rendered until the index landed and the longest interval between two of them (`jank`). The Flutter fixture computes the stage's rows on the UI isolate in the click handler (sort by pre-parsed price, filter, group with aggregates), measures the handler through the post-frame callback of the frame that shows them, and reads the same two figures from `FrameTiming` between the frame current at the click and that frame, waiting a moment before saving so the last batch of timings is in. Neither figure is a presentation time.

GPUIX moves 60 logical pixels for a -120 wheel delta on this machine and Flutter moves 80 (linear in the delta, measured with [calibrate-wheel.ps1](calibrate-wheel.ps1) at 60 events per second); Kit/Shell move 78. The runner uses -156 for GPUIX, -117 for Flutter and -120 for the other fixtures, so every fixture moves 78 logical pixels per event. Recheck calibration after changing display, OS scrolling settings or dependencies. The driver waits on a high resolution waitable timer at a one-millisecond system timer resolution, raises itself to the high priority class for the run, holds the display awake for the run (injected input is not user presence, so an unattended machine would otherwise turn its display off and lock; a locked session fails the activation with the covering window named), pays the first-call cost of the input path before the measured window, keeps its 250 ms process sampling out of the eight milliseconds before an input deadline, and places the pointer over the target before measuring input; `run.json` records the timer resolution and whether the elevation took. Late driver deadlines are counted and skipped, and every injected click must match the application's update count. These are **missed input deadlines**, not missed display frames.

## Capture foreground measurements

Start from a foreground PowerShell session and keep the desktop free while it runs. CPU, memory and application diagnostics do not require ETW access. Measure the two implementations using the same GPUI Kit table first:

```powershell
./benchmarks/suite.ps1 -RunId paired -Implementations rust,dart -Repetitions 3 -Seconds 10
./benchmarks/summarize-pair.ps1 -RunPrefix paired -Repetitions 3
```

Then measure all four implementations. Four repetitions rotate each implementation through every position:

```powershell
./benchmarks/suite.ps1 -RunId comparison -Repetitions 4 -Seconds 10
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-0
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-1
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-2
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-3
```

Add `-CapturePresent` when the session has permission to start an ETW trace through administrator access or an appropriately configured Performance Log Users membership. Capturing ETW still requires update-to-frame correlation before reporting response latency.

Each run takes roughly 15–20 seconds including warmup and shutdown. Use `-Repetitions 1` for a capture preflight. The runner stops if its target loses foreground focus. It does not change account privileges. If PresentMon fails, it retains the error log and records presentation as unavailable.

To compare Dart with the JavaScript fixtures in three rotated orders:

```powershell
./benchmarks/suite.ps1 -RunId dart-js -Repetitions 3 -Seconds 10 -Implementations dart,solid,shell
./benchmarks/summarize-pair.ps1 -RunPrefix dart-js -Repetitions 3 -Implementations dart,solid,shell
```

The same pair of commands with `-Implementations dart,flutter` and a `dart-flutter` run ID compares the SDK with a Flutter Windows application built on the same machine. The summary defaults to Rust/Dart and accepts an explicit implementation list. It retains all attempts, keeps publication/drawing percentiles per run, and summarizes process CPU and memory across completed runs. Solid's overlay and Shell's build counters remain separate from Dart's native diagnostics. After an interruption, `./benchmarks/resume-series.ps1 -RunPrefix paired -Repetitions 3 -Implementations rust,dart` reruns every slot without a result under the next retry run ID (`paired-1-retry1` and so on) and skips finished ones, so it can be rerun until the series is complete. The runner refuses to reuse an attempt with a result or failure record. The summary includes retry directories alongside the original failure. The schedule uses an integer slot count to prevent input at or beyond the requested interval boundary.

If Windows denies programmatic foreground activation, the runner temporarily exposes its own window, verifies the activation point belongs to that window, clicks an empty area, and restores ordinary window ordering before warmup. Activation clicks are recorded separately from workload input.

## Trace missing updates

After building the regular fixtures, build the diagnostic Rust executable and Dart DLL:

```powershell
./benchmarks/build-trace.ps1
./benchmarks/run.ps1 -Implementation rust -Workload cell -Seconds 10 -RunId trace -TraceInput
./benchmarks/analyze-input.ps1 -Directory reports/comparison/trace/rust-cell
./benchmarks/run.ps1 -Implementation dart -Workload burst -Seconds 10 -RunId trace -TraceInput
./benchmarks/analyze-input.ps1 -Directory reports/comparison/trace/dart-burst
```

The build script copies diagnostic binaries into `build/comparison-trace`, then restores ordinary release binaries. The `benchmark-trace` Cargo feature is disabled for performance measurements. `-NoPointerWarmup` reproduces the earlier driver's lack of a hover-settling interval.

Each click carries a sequence tag in `SendInput` metadata. Native tracing records GPUI mouse down/up, entry into the click handler, application handling, application of the update and state readback. Dart traces include the native sequence, target dataset revision, acknowledgement and a native cell diagnostic read. Trace runs perform extra work and are excluded from performance comparisons. QPC and Dart elapsed timestamps do not establish presentation latency.

The analyzer reports the first missing stage for each injected sequence. A missing native mouse event does not establish driver fault. Preserve the original failure and inspect injection acceptance, coordinates and focus before assigning a cause.

Completed runs with incorrect update counts or state still write `run.json`, including process measurements and a failed `correctness` result. The runner exits with code 2, and the suite retains the observation and continues. Interrupted observations write `failure.json`; the analyzer includes them in reliability accounting. Equal-work timing eligibility is a separate field.

```powershell
./benchmarks/test-input-analysis.ps1
./benchmarks/test-analysis.ps1
```

To check a copied runtime package with an unrelated working directory and a Windows-only `PATH`:

```powershell
./benchmarks/run.ps1 -Implementation dart -Workload cell -Seconds 2 -RunId package-check -BackgroundSmoke -Packaged
```

Repeat for `rust`, `shell`, `solid` and `flutter`. This remains a development-machine check, not a clean-machine test.

Before ranking implementations, inspect screenshots, wheel displacement, input counts and machine load. Keep incorrect-work and unequal-cadence observations in the reliability report, and exclude them from the equal-work timing subset. Run the fixtures serially. Record display mode, power mode and graphics driver versions with the captures; [environment.json](../reports/environment.json) is the existing machine inventory.

## What the outputs mean

| Output | Boundary and limitations |
| --- | --- |
| `run.json` | QPC input times, measured interval, driver misses, process CPU, private bytes, working set and executable hash. CPU percent uses one logical core as 100%. |
| `application.json` | Data/scroll correctness and implementation-specific diagnostics. Rust/Dart histograms include startup and warmup. GPUIX exports the last 1,000 draws, p90 and p99, without p95. Flutter reports `FrameTiming` build, raster and total-span percentiles over every frame since startup, plus its row build count. These histories are not directly comparable. |
| `present.csv` | PresentMon 2.6.0 ETW records. The analyzer filters to the target PID and CPU-start QPC interval, and rejects multiple swapchains. It excludes the first interval that started outside the measured window. |
| `analysis.json` | Per-run process metrics, application diagnostics with their original scope, present/display intervals and undisplayed-frame count, when available. Process/presentation percentiles use nearest rank; application histograms retain their own estimators. No averages of percentiles across runs. |
| `failure.json` | Interrupted or legacy failed observation, error and any recorded input schedule. Kept in reliability accounting. Completed correctness failures remain in `run.json`. |
| Estimated missed workload slots | Rounded display interval/target cadence minus one, clamped at zero. Idle is undefined. This is an estimate relative to the workload cadence, not proof of a missed physical refresh. |
| Input-associated display | PresentMon's input association. A hover or pressed-button frame can precede the changed cell, especially with asynchronous callbacks. |
| Input-to-response-present | From a traced run with `present.csv`: the diagnostic build records the first content paint of each applied revision (`content_painted`), the input analyzer takes the first PresentMon record of the target process whose CPU start follows that paint, and reports present start and display (start plus PresentMon `DisplayLatency`) relative to the injected input's QPC. `analyze.ps1` copies the summary when `input-analysis.json` sits beside the run. Diagnostic builds only; an ETW capture needs administrator access or Performance Log Users membership. |
| Window availability | Process launch to HWND discovery. It does not establish startup to first fully rendered/displayed UI; Flutter's runner creates its window before its engine starts. |
| First content and first frame | `first_content_ms` is the driver's first `PrintWindow` capture after showing the window whose client area holds more than one color, polled every 5 ms; `application_first_frame_ms` is the fixture's own first frame against the launch instant the runner passes in `GPUIDART_BENCH_LAUNCH_UTC_MS`. Both are composited or app-side readings, not PresentMon present times. |
| Payload size | Explicit executable/runtime/script/CRT files in `build/comparison`. Clean-machine dependency closure and bytes created on first launch remain unverified. |

Publication-stage diagnostics remain in the Dart application's report. They are not added to frame or input percentiles. The architecture comparison remains incomplete until response-frame correlation, foreground ETW captures and widget parity have been reviewed. No runtime winner follows from the background checks.

Production packaging must also configure DPI awareness before window creation. The benchmark-only setting does not fix the shipping demo. See the [production DPI requirement](../docs/integration.md#windows-production-dpi-requirement).

PresentMon definitions: [official console documentation, v2.6.0](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md).
