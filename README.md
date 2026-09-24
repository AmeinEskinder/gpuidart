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

The example opens a native GPUI window. Increment the counter, type into the input, and scroll the 10,000-row table. A Dart timer changes the status after two seconds. Input text and focus survive description replacement.

For a release build:

```powershell
./tool/build.ps1 -Release
$env:GPUIDART_LIBRARY = "$PWD/target/release/gpuidart.dll"
dart run example/main.dart
```

## Verify

```powershell
./tool/check.ps1
```

The native tests render GPUI controls and exercise pointer/keyboard input, focus retention, table virtualization, callback-free repaints, invalid descriptions, stale revisions and removal of retained state. The Dart integration test briefly opens a real native window, publishes from a timer, checks rejection/recovery and closes the application.

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
- One whole-view snapshot per publication. No signals, node patches, hot reload, child-view snapshots or embedded Dart VM implementation yet.
- Descriptions use UTF-8 JSON and copy table data on every publication. This is a correctness baseline, not a performance result.
- Tables render cells entirely in Rust. Dart provides strings; arbitrary Dart row render callbacks, sorting and stable row identity are not implemented. Table selection follows row indices.
- The adapter uses a fixed column layout and component theme. It is not a complete GPUI style binding.

GPUI Kit is pinned to commit `21622a70efd25219d26aa459164878c4da9e39f8`; its GPUI dependency is `gpui-pre` 0.3.6. Both Cargo and Dart dependency lockfiles are included.

