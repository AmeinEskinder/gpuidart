# Four implementation comparison

The production GPUI-Dart adapter is unchanged. These fixtures use its existing whole-view snapshots and dataset API.

## Build

From the repository root, with the existing Rust/MSVC, Dart and Bun toolchains:

```powershell
./benchmarks/build.ps1
./benchmarks/install-presentmon.ps1
```

The native reference uses Rust state and GPUI Kit controls directly. Shell uses QuickJS, its stock component host for buttons, and `uniform_list` for table rows. Solid uses the published `@gpuix/solid` and native addon, both 0.10.0. Dart is compiled to an AOT executable. Pins, build descriptions, lockfile hashes and payload hashes are in [artifacts.json](../reports/comparison/artifacts.json).

The Shell component `DataTable` is unsuitable for this fixture at the pinned revision: its data callback exceeds the host's 4,096-value/1,024-object-key limits. Its default columns are also 100 pixels, with no exposed width setter. The virtual-list fixture avoids modifying those host limits. It is a different widget implementation from GPUI Kit's DataTable; results must retain that qualification. Shell's `check` command also panics on this virtual-list fixture because it materializes outside a rendering view. The live window checks pass.

## Verify the fixtures

```powershell
./benchmarks/suite.ps1 -RunId smoke -Repetitions 1 -Seconds 2 -BackgroundSmoke
./benchmarks/analyze.ps1 -Directory reports/comparison/smoke-0
./benchmarks/test-analysis.ps1
```

Background checks post window messages to the application's own HWND. They verify edits, scrolling and the native window's rendered image through `PrintWindow`. They do not measure physical input or display presentation. The analyzer excludes them from performance results.

Each fixture has 100,000 identical records, three 200-pixel columns, 32-pixel rows, a 320-pixel table viewport, 16-pixel text and an 860 × 650 logical-pixel client area. Captures on this machine are 1075 × 812 physical pixels at 125% scaling. The Dart benchmark selects per-monitor DPI awareness before starting GPUI; without that startup setting, Windows bitmap scaling makes its render resolution different. This setup is confined to the benchmark entry point. All fixtures construct only rows near the viewport; Solid retains a window of 32 row components. GPUI Kit adds selection, column controls and a scrollbar that the two list fixtures do not reproduce. Header separators and rounding also differ slightly.

The workloads run in fresh processes after a three-second warmup:

| Workload | Input |
| --- | --- |
| Idle | No updates |
| Scroll | 60 wheel events/second, calibrated to 78 logical pixels/event |
| Cell | 5 clicks/second, each changes row 0's price |
| Burst | 30 clicks/second, each changes prices in visible rows 0–7 |

GPUIX's wheel input uses 60 pixels for a -120 wheel delta on this machine; Kit/Shell use 78. The runner uses -156 for GPUIX and -120 for the other fixtures. Recheck calibration after changing display, OS scrolling settings or dependencies. The driver waits on a high resolution waitable timer and places the pointer over the target before measuring input. Late driver deadlines are counted and skipped, and every injected click must match the application's update count. These are **missed input deadlines**, not missed display frames.

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

The summary defaults to Rust/Dart and accepts an explicit implementation list. It retains all attempts, keeps publication/drawing percentiles per run, and summarizes process CPU and memory across completed runs. Solid's overlay and Shell's build counters remain separate from Dart's native diagnostics. After an interruption, use a fresh run ID such as `paired-1-retry1` for that case. The runner refuses to reuse an attempt with a result or failure record. The summary includes retry directories alongside the original failure. The schedule uses an integer slot count to prevent input at or beyond the requested interval boundary.

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

Repeat for `rust`, `shell`, and `solid`. This remains a development-machine check, not a clean-machine test.

Before ranking implementations, inspect screenshots, wheel displacement, input counts and machine load. Keep incorrect-work and unequal-cadence observations in the reliability report, and exclude them from the equal-work timing subset. Run the fixtures serially. Record display mode, power mode and graphics driver versions with the captures; [environment.json](../reports/environment.json) is the existing machine inventory.

## What the outputs mean

| Output | Boundary and limitations |
| --- | --- |
| `run.json` | QPC input times, measured interval, driver misses, process CPU, private bytes, working set and executable hash. CPU percent uses one logical core as 100%. |
| `application.json` | Data/scroll correctness and implementation-specific diagnostics. Rust/Dart histograms include startup and warmup. GPUIX exports the last 1,000 draws, p90 and p99, without p95. These histories are not directly comparable. |
| `present.csv` | PresentMon 2.6.0 ETW records. The analyzer filters to the target PID and CPU-start QPC interval, and rejects multiple swapchains. It excludes the first interval that started outside the measured window. |
| `analysis.json` | Per-run process metrics, application diagnostics with their original scope, present/display intervals and undisplayed-frame count, when available. Process/presentation percentiles use nearest rank; application histograms retain their own estimators. No averages of percentiles across runs. |
| `failure.json` | Interrupted or legacy failed observation, error and any recorded input schedule. Kept in reliability accounting. Completed correctness failures remain in `run.json`. |
| Estimated missed workload slots | Rounded display interval/target cadence minus one, clamped at zero. Idle is undefined. This is an estimate relative to the workload cadence, not proof of a missed physical refresh. |
| Input-associated display | PresentMon's input association. A hover or pressed-button frame can precede the changed cell, especially with asynchronous callbacks. **Input-to-response-present remains null until the changed frame is correlated with its input sequence.** |
| Window availability | Process launch to HWND discovery. It does not establish startup to first fully rendered/displayed UI. |
| Payload size | Explicit executable/runtime/script/CRT files in `build/comparison`. Clean-machine dependency closure and bytes created on first launch remain unverified. |

Publication-stage diagnostics remain in the Dart application's report. They are not added to frame or input percentiles. The architecture comparison remains incomplete until response-frame correlation, foreground ETW captures and widget parity have been reviewed. No runtime winner follows from the background checks.

Production packaging must also configure DPI awareness before window creation. The benchmark-only setting does not fix the shipping demo. See the [production DPI requirement](../docs/integration.md#windows-production-dpi-requirement).

PresentMon definitions: [official console documentation, v2.6.0](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md).
