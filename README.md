# GPUI-Dart

An experimental desktop SDK using Dart application code and GPUI Kit's Rust controls. Start with the [SDK guide](docs/sdk.md) and the [Market watch example](example/watchlist/main.dart).

| Target | Verified scope |
| --- | --- |
| Windows x64 | Reference host, local desktop checks and AOT packaging |
| macOS 15 ARM64 | Hosted native-window lifecycle, JIT/AOT 100k workload and code reload; GPUI runs in a native main-thread companion |
| Ubuntu 24.04 x64, X11 | Hosted Xvfb/Mesa window lifecycle, JIT/AOT 100k workload and code reload |

See [cross-platform acceptance](reports/cross-platform/status.md) for source revisions, package results and remaining gates. Native Wayland, Intel Macs, other Linux distributions and older macOS versions are unverified.

The current [MVP release candidate](reports/mvp/README.md) passed all nine local acceptance checks. Its [Windows ZIP](build/WatchlistMvp-windows-x64.zip) is built from committed source. Clean-machine launch, human IME verification and an [unlocalized reload observation](reports/mvp/attempt-023eef4/README.md) remain open before calling the release stable. Reproduce local acceptance with `./tool/verify_mvp.ps1`.

The SDK supports row/column layouts, text, buttons, native text inputs and virtualized tables, plus initial window options and table-selection events. Dart submits a whole UI description through FFI. Rust owns the description and retained control state. Native events return asynchronously, leaving Dart timers and Futures free to run.

Table datasets upload once. View snapshots reference them by ID; cell and row edits transfer only changed data. See [the dataset API](docs/datasets.md) and [100,000-record acceptance measurements](reports/data-publication.md).

This implements a small direct adapter over GPUI Kit. It does not replace Shell's QuickJS engine. See [the integration decision](docs/integration.md) for the source findings and next experiments.

## Run

Requirements: Windows x64, Dart 3.13+, Rust 1.98.1, MSVC x64 build tools and a Windows SDK. A project-local Rust/MSVC installation is already present in this workspace under `.tools`; the scripts discover it. On another machine, install the standard Rust and Visual Studio C++ toolchains first.

From this directory in PowerShell:

```powershell
./tool/build.ps1
dart run tool/dev.dart
```

Market watch opens a native GPUI window with 1,000 fictitious instruments. Search by symbol, select a row, add it to your shortlist, sort by price and simulate a price update. Search and the shortlist toggle are a native view over the dataset: filtering and sorting never move or republish records, selection survives them by stable record ID, and prices/changes render through declarative number formats with color and icon rules. Ctrl+F focuses search and Ctrl+Enter saves the selected record as scoped key actions. Input text, focus, selection and scroll state survive ordinary description replacement. State is in memory. The earlier counter and 10,000-row measurement example remains in example/main.dart.

For a release build:

```powershell
./tool/build.ps1 -Release
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run example/watchlist/main.dart
```

## Portable Windows package

```powershell
./tool/package.ps1
./tool/verify_package.ps1
```

The output is [build/gpuidart-windows-x64.zip](build/gpuidart-windows-x64.zip). Extract it and run `gpuidart.exe`; keep its DLLs beside it. The executable includes Dart's AOT runtime. The ZIP includes the native GPUI library and release Visual C++ runtime. On a machine without the project-local CRT archive, supply `-CrtDirectory` pointing to the Microsoft x64 redistributable folder.

Verification extracts the ZIP outside the repository, changes to an unrelated working directory, restricts PATH to Windows directories and runs the watchlist's self-test. It checks loaded module paths, including Common Controls v6 and the sibling CRT, and the actual window's PerMonitorV2 awareness. The executable embeds a DPI manifest. A clean machine without an SDK has not yet been tested. The ZIP includes a standalone verifier and [manual release checks](docs/windows-release-checks.md).

## macOS and Linux

Use Dart 3.13.4 and the pinned Rust toolchain. The macOS build was verified with Xcode 16.4 and its Metal tools; Linux needs the build dependencies listed in [its workflow](.github/workflows/linux.yml). On Linux, select X11 with `DISPLAY` set and `WAYLAND_DISPLAY`/`ZED_HEADLESS` unset.

```sh
dart run tool/build.dart
dart run tool/dev.dart
dart run tool/check.dart
dart run tool/package.dart --name=Watchlist
```

The package command emits `build/Watchlist-macos-arm64.tar.gz` or `build/Watchlist-linux-x64.tar.gz`. Run `dart run tool/verify_package.dart ARCHIVE REPORT.json` to extract and verify it. See [Unix release checks](docs/unix-release-checks.md) for runtime libraries, macOS signing limits and human input/display checks. macOS bundles currently use ad-hoc signatures; public distribution and clean-Mac launch remain unverified.

## Development code reload

```powershell
./tool/build.ps1
dart run tool/dev.dart
```

The launcher watches the chosen entry point's directory and lib. Change WatchlistApplication.heading in [the watchlist component](example/watchlist/app.dart) and save. The development runner uses the VM service to reload changed code, then calls the existing view builder again. Existing Dart objects and native control entities remain alive. Close the window to exit. Use `dart run tool/dev.dart example/main.dart` for the earlier demo, or provide your own entry point and arguments.

This supports component method edits in Dart JIT development mode. It follows Dart's reload restrictions, does not rerun `main` or initializers, and does not reload AOT packages or Rust code. Changes to startup registration may require a restart.

The automated code-change test uses a source copy under `.cache`, keeps the process and isolate running, and checks both Dart and native state. It also rejects invalid source without replacing the live code:

```powershell
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run tool/verify_reload.dart
dart run tool/verify_watchlist_reload.dart
dart run tool/verify_watchlist_ui.dart
dart run tool/verify_dev_launcher.dart
```

## Measurements

See [the recorded results and limitations](reports/summary.md). The host separately counts registered Dart description builds, encodes, all FFI callbacks, UI callbacks, native view materializations, and row/cell construction calls. Native profiling records draw and presentation-submission timings. Application acknowledgement is not a display fence.

```powershell
./tool/verify_package.ps1
. ./tool/env.ps1
$env:GPUIDART_VIRTUALIZATION_REPORT = "$PWD/reports/virtualization.json"
cargo test --locked -p gpuidart construction_and_allocations_scale_with_viewport
dart run tool/verify_reload.dart
dart run tool/summarize.dart
```

`reports/environment.json` describes the machine used for the recorded run; refresh it when measuring elsewhere. Native histograms include startup, forced repaints and updates together. The earlier 120-update workload changes one visible price through a dataset edit and a counter through a view snapshot. Run `dart run tool/measure_data.dart` for separate cell, row, ten-cell and counter measurements at up to 100,000 records. [Three repetitions against Shell and GPUIX/Solid](reports/comparison/dart-js-20260925.md) are complete, with implementation differences and timing limits recorded. [SDK verification](reports/sdk/README.md) is separate from those historical performance captures.

## Verify

```powershell
./tool/check.ps1
```

The native tests render GPUI controls and exercise pointer/keyboard input, Unicode selection, table navigation, wheel scrolling, resizing, retained state, callback-free repaints, invalid descriptions, stale revisions and removal of retained state. A separate allocator probe measures redraw work for 100, 10,000 and 100,000 records. The Dart integration test briefly opens a real native window, publishes from a timer, checks rejection/recovery and closes the application. Headless interaction tests do not replace human visual inspection.

`cargo test` and `cargo build` produce different native artifacts. The check script builds the normal DLL before running Dart.

The check script also builds a test library that injects protocol and shutdown failures. See [failure handling](docs/failures.md) for deadlines, panic-containment limits and regression coverage. [GitHub Actions](docs/ci.md) runs Windows headless checks and separate headless/window jobs on macOS and Linux. Hosted and human verification remain distinct.

## Example

```dart
final host = await GpuiHost.open(UiColumn('root', [
  const UiText('message', 'Hello from Dart'),
  const UiButton('save', 'Save'),
  const UiInput('name', placeholder: 'Name'),
]));

host.events.listen((event) {
  if (event.type == 'click' && event.id == 'save') {
    print('Save clicked');
  }
});

await host.done;
```

Node IDs must be nonempty and unique throughout one description. An input or table keeps its native entity when the same ID and control kind appear in the next description. Removing it drops the retained entity and subscription. Inputs are currently uncontrolled; Dart receives changes, and the native input owns its text, cursor, selection and undo history.

`publish` completes when Rust applies the description. It does not measure when the GPU presents the frame. The native queue holds up to 64 commands and rejects submissions when full. Callers must await or handle publication failures.

## Current limits

The remaining clean-Windows launch and human IME checks have a [setup guide](docs/windows-test-setup.md), an automatic Sandbox runner and an observation sheet. Windows feature installation requires administrator access; neither generated test files nor installed language components count as completed verification.

The [four-implementation benchmark](benchmarks/README.md) contains Rust, Shell/QuickJS, GPUIX/Solid and Dart AOT fixtures, repeatable Windows input, and separate publication/presentation measurements. See the [comparison status](reports/comparison/README.md) for completed checks and measurement gaps.

- One application host with one window. Windows and Linux X11 use a blocking native runner isolate; macOS uses a native companion process whose main thread owns GPUI.
- One whole-view snapshot per publication. No signals, node patches, child-view snapshots or Rust executable embedding the Dart VM.
- Descriptions use UTF-8 JSON. Table datasets upload once; edits send changed records. Initial upload, full replacement and storage grow with row count.
- Tables render cells entirely in Rust. Dart provides strings; arbitrary Dart row render callbacks, sorting and stable row identity are not implemented. Table selection follows row indices.
- The adapter has a small row/column layout API and fixed component theme. It is not a complete GPUI style binding.

GPUI Kit is pinned to commit `21622a70efd25219d26aa459164878c4da9e39f8`; its GPUI dependency is `gpui-pre` 0.3.6. Both Cargo and Dart dependency lockfiles are included.
