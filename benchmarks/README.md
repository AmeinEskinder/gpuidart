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

GPUIX's wheel input uses 60 pixels for a -120 wheel delta on this machine; Kit/Shell use 78. The runner uses -156 for GPUIX and -120 for the other fixtures. Recheck calibration after changing display, OS scrolling settings or dependencies. A high resolution timer is requested for the driver. Late driver deadlines are counted and skipped, and every delivered click must match the application's update count. These are **missed input deadlines**, not missed display frames.

## Capture foreground measurements

Start this from a foreground PowerShell session with permission to start an ETW trace (administrator or appropriately configured Performance Log Users membership). Keep the desktop free while it runs:

```powershell
./benchmarks/suite.ps1 -RunId comparison -Repetitions 3 -Seconds 10 -CapturePresent
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-0
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-1
./benchmarks/analyze.ps1 -Directory reports/comparison/comparison-2
```

Each run takes roughly 15–20 seconds including warmup and shutdown. Use `-Repetitions 1` for a capture preflight. The runner stops if its target loses foreground focus. It does not change account privileges. If PresentMon fails, it retains the error log and records presentation as unavailable.

To check a copied runtime package with an unrelated working directory and a Windows-only `PATH`:

```powershell
./benchmarks/run.ps1 -Implementation dart -Workload cell -Seconds 2 -RunId package-check -BackgroundSmoke -Packaged
```

Repeat for `rust`, `shell`, and `solid`. This remains a development-machine check, not a clean-machine test.

Before ranking implementations, inspect the screenshots, verify wheel displacement and delivered input counts, and reject runs with driver deadline misses or unrelated machine load. Run the fixtures serially. Record display mode, power mode and graphics driver versions with the captures; [environment.json](../reports/environment.json) is the existing machine inventory.

## What the outputs mean

| Output | Boundary and limitations |
| --- | --- |
| `run.json` | QPC input times, measured interval, driver misses, process CPU, private bytes, working set and executable hash. CPU percent uses one logical core as 100%. |
| `application.json` | Data/scroll correctness and implementation-specific diagnostics. Rust/Dart histograms include startup and warmup. GPUIX exports the last 1,000 draws, p90 and p99, without p95. These histories are not directly comparable. |
| `present.csv` | PresentMon 2.6.0 ETW records. The analyzer filters to the target PID and CPU-start QPC interval, and rejects multiple swapchains. It excludes the first interval that started outside the measured window. |
| `analysis.json` | Per-run process metrics, present/display intervals and undisplayed-frame count, when available. Percentiles use nearest rank. No averages of percentiles across runs. |
| Estimated missed workload slots | Rounded display interval/target cadence minus one, clamped at zero. Idle is undefined. This is an estimate relative to the workload cadence, not proof of a missed physical refresh. |
| Input-associated display | PresentMon's input association. A hover or pressed-button frame can precede the changed cell, especially with asynchronous callbacks. **Input-to-response-present remains null until the changed frame is correlated with its input sequence.** |
| Window availability | Process launch to HWND discovery. It does not establish startup to first fully rendered/displayed UI. |
| Payload size | Explicit executable/runtime/script/CRT files in `build/comparison`. Clean-machine dependency closure and bytes created on first launch remain unverified. |

Publication-stage diagnostics remain in the Dart application's report. They are not added to frame or input percentiles. The architecture comparison remains incomplete until response-frame correlation, foreground ETW captures and widget parity have been reviewed. No runtime winner follows from the background checks.

PresentMon definitions: [official console documentation, v2.6.0](https://github.com/GameTechDev/PresentMon/blob/v2.6.0/README-ConsoleApplication.md).
