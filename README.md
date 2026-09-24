# GPUI-Dart

An experimental Windows desktop host using Dart application code and GPUI Kit's Rust controls.

The first spike supports text, buttons, native text inputs and virtualized tables. Dart submits a whole UI description through FFI. Rust owns the description and retained control state. Native events return asynchronously, leaving Dart timers and Futures free to run.

This implements a small direct adapter over GPUI Kit. It does not replace Shell's QuickJS engine. See [the integration decision](docs/integration.md) for the source findings and next experiments.

## Run

Requirements: Windows x64, Dart 3.13+, Rust 1.98.1, MSVC x64 build tools and a Windows SDK. A project-local Rust/MSVC installation is already present in this workspace under `.tools`; the scripts discover it. On another machine, install the standard Rust and Visual Studio C++ toolchains first.

From this directory in PowerShell:

```powershell
./tool/build.ps1
dart run example/main.dart
```

The example opens a native GPUI window. Increment the counter, type into the input, and scroll the 10,000-row table. Input text, focus, selection and scroll state survive description replacement.

For a release build:

```powershell
./tool/build.ps1 -Release
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run example/main.dart
```

## Portable Windows package

```powershell
./tool/package.ps1
./tool/verify_package.ps1
```

The output is [build/gpuidart-windows-x64.zip](build/gpuidart-windows-x64.zip). Extract it and run `gpuidart.exe`; keep its DLLs beside it. The executable includes Dart's AOT runtime. The ZIP includes the native GPUI library and release Visual C++ runtime. On a machine without the project-local CRT archive, supply `-CrtDirectory` pointing to the Microsoft x64 redistributable folder.

Verification extracts the ZIP outside the repository, changes to an unrelated working directory, restricts PATH to Windows directories and runs `--self-test` and `--measure`. It checks loaded module paths, including Common Controls v6. A clean machine without an SDK has not yet been tested.

## Development code reload

```powershell
./tool/build.ps1
dart run tool/dev.dart
```

Save a Dart file under `example/` or `lib/` to reload. For a simple example, change `DemoApplication.heading` in [example/app.dart](example/app.dart). The development runner uses the VM service to reload changed code, then calls the existing view builder again. Existing Dart objects and native control entities remain alive. Close the window to exit.

This supports component method edits in Dart JIT development mode. It follows Dart's reload restrictions, does not rerun `main` or initializers, and does not reload AOT packages or Rust code. Changes to startup registration may require a restart.

The automated code-change test uses a source copy under `.cache`, keeps the process and isolate running, and checks both Dart and native state. It also rejects invalid source without replacing the live code:

```powershell
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run tool/verify_reload.dart
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

`reports/environment.json` describes the machine used for the checked-in run; refresh it when measuring elsewhere. Native histograms include startup, forced repaints and updates together. The 120-update workload changes one visible price and a counter through whole-view snapshots. It has not yet been compared with matched GPUI Shell or GPUIX workloads.

## Verify

```powershell
./tool/check.ps1
```

The native tests render GPUI controls and exercise pointer/keyboard input, Unicode selection, table navigation, wheel scrolling, resizing, retained state, callback-free repaints, invalid descriptions, stale revisions and removal of retained state. A separate allocator probe measures redraw work for 100, 10,000 and 100,000 records. The Dart integration test briefly opens a real native window, publishes from a timer, checks rejection/recovery and closes the application. Headless interaction tests do not replace human visual inspection.

`cargo test` and `cargo build` produce different native artifacts. The check script builds the normal DLL before running Dart.

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

- Windows only, one application host with one window. The dedicated UI isolate is a Windows experiment; macOS needs a different launch/thread arrangement.
- One whole-view snapshot per publication. No signals, node patches, child-view snapshots or Rust executable embedding the Dart VM.
- Descriptions use UTF-8 JSON and copy table data on every publication. Rendering is virtualized; total data storage and publication work still grow with row count.
- Tables render cells entirely in Rust. Dart provides strings; arbitrary Dart row render callbacks, sorting and stable row identity are not implemented. Table selection follows row indices.
- The adapter uses a fixed column layout and component theme. It is not a complete GPUI style binding.

GPUI Kit is pinned to commit `21622a70efd25219d26aa459164878c4da9e39f8`; its GPUI dependency is `gpui-pre` 0.3.6. Both Cargo and Dart dependency lockfiles are included.
