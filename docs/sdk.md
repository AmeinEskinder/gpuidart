# Windows SDK preview

GPUI-Dart 0.1 is a Windows x64 SDK preview. DPI setup requires Windows 10 version 1803 or later, using Microsoft's [process DPI-context API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiawarenesscontextforprocess); this build was tested on Windows 11. The supported application model is one host and one window per process, immutable UI descriptions, and retained native controls and datasets. The JSON wire format and diagnostic commands are internal. Build the Dart package and native DLL from the same revision.

The Dart host checks native ABI/protocol version 1 before creating a host. Older DLLs without a version export, and DLLs with a different version, fail with a rebuild instruction. The native library rejects a second active host, including callers from another Dart isolate. Await the previous host's done Future before opening another one.

## Run the representative screen

From the repository root:

```powershell
./tool/build.ps1
dart run tool/dev.dart
```

The default entry point is [Market watch](../example/watchlist/main.dart). It contains 1,000 fictitious instruments, search, row selection, a shortlist and sample price updates. Search replaces the displayed dataset deliberately; updating a price or shortlist entry sends one cell edit. There is no live feed or trading connection. Application data is in memory and resets when the process exits.

Select a row, add it to the shortlist, simulate a price update, and switch to the shortlist. Editing the search preserves the native input and replaces the table records. Dataset replacement clears selection and resets scrolling. Ordinary view rebuilds and code reload preserve those native entities.

For another entry point:

```powershell
dart run tool/dev.dart example/main.dart
dart run tool/dev.dart path/to/main.dart --your-app-argument
```

Run the launcher from the project root. It watches the entry point's directory recursively and the package's lib directory. It reports compilation/reload errors and keeps the previous running code on a rejected reload. Rust changes and Dart changes that the VM cannot reload require a restart. Close the application window to stop the launcher.

Startup waits at most 30 seconds for reload registration. Failed startup cleans up the launched process tree, including Dart's VM child process. Ctrl+C requests application shutdown. Reload service calls also have a timeout, so an unavailable application does not leave the launcher waiting indefinitely.

## Application lifecycle

```dart
import 'package:gpuidart/gpuidart.dart';
import 'package:gpuidart/development.dart';

final data = TableDataset('records', columns: ['Name'], rows: [['First']]);
final host = await GpuiHost.openView(
  () => UiColumn('root', [
    const UiInput('search', placeholder: 'Search'),
    const UiTable('table', dataset: 'records'),
  ]),
  datasets: [data],
  window: const GpuiWindowOptions(title: 'My application', width: 960, height: 720),
);
registerGpuiReload(host);
final subscription = host.events.listen((event) {
  final selection = event.tableSelection;
  if (selection != null && selection.datasetRevision == data.revision) {
    print(selection.row); // Null means selection was cleared.
  }
});
try {
  await host.done;
} finally {
  await host.close();
  await subscription.cancel();
}
```

Put the application object outside its build method. Register its existing build method with openView; rebuild executes that method and publishes a whole-view snapshot. registerGpuiReload supplies the development launcher's reassemble/close extensions and does nothing in product AOT builds. Reload does not rerun main or field initializers.

Serialise asynchronous UI handlers that touch the same dataset. The watchlist's event queue is an example. Every dataset transaction must finish before the next one begins. Surface failures to the application; do not discard publication Futures. Stop timers/subscriptions during shutdown, and await close or done before exiting.

## Public contract

| API | Contract |
| --- | --- |
| UiColumn / UiRow | Vertical/horizontal groups with the native theme's standard spacing. Rows wrap when space is limited. The screen scrolls vertically when its content exceeds the window. |
| UiText / UiButton | Text and native button. Click events carry node ID and snapshot revision. |
| UiInput | Native input owns text, cursor, selection, undo and composition. Dart receives input events. No controlled-value setter is exposed. |
| UiTable | References a registered dataset ID. Cells contain strings and render in Rust. |
| GpuiWindowOptions | Initial title and logical width/height. Width 320..8192, height 240..8192. Window sizing is independent of display scale. |
| GpuiEvent.tableSelection | Typed row-selection data with table ID, dataset ID and dataset revision. Ignore an index from a revision that the application no longer holds. |
| publish / rebuild | Completes after native application of a snapshot. This is not a presentation fence. |
| registerDataset / editDataset / replaceDataset / releaseDataset | Revisioned transactions; Dart data commits after native acknowledgement. See [datasets](datasets.md). |
| close / done | Close is idempotent; done completes after the native UI loop and callback teardown finish. Pending publications settle with success or an error. A paused event subscriber does not delay done; it receives queued events and stream completion when resumed. |

Node IDs are nonempty and unique across the whole description, including nested rows. Reusing an ID and control kind preserves its native state. Removing the node releases its retained entity. Changing a table's dataset or replacing a dataset resets selection and scroll. Row indices are not stable record identities; the watchlist keeps an instrument symbol in application state.

Snapshots have at most 4,096 nodes, depth 32 and 16 MiB encoded size. Datasets have at most 100,000 rows and 64 columns. The native command queue has 64 slots. Invalid descriptions, stale revisions, a full/closed queue and overlapping transactions are errors. Await or handle the returned Future.

## Package an AOT application

```powershell
./tool/package.ps1
./tool/verify_package.ps1
```

The default output is build/gpuidart-windows-x64.zip. The directory beside it contains the executable, GPUI DLL, release CRT, license, manifest of file hashes and a standalone verification script. The executable embeds a PerMonitorV2 application manifest. The shared host also selects or verifies that awareness before opening GPUI, which covers dart run and launchers with the same setting already applied. Conflicting earlier DPI configuration fails with an actionable error.

The package verifier extracts outside the repository, uses an unrelated working directory and Windows-only PATH, runs the application's self-test, checks package hashes/loaded DLL paths and queries the actual window's DPI-awareness context. These local checks do not establish clean-machine dependency closure.

Custom entry point and filename:

```powershell
./tool/package.ps1 -EntryPoint path/to/main.dart -Name MyApp
./tool/verify_package.ps1 -Zip build/MyApp-windows-x64.zip
```

The verifier expects a --self-test mode that exits successfully and prints one JSON object with mode set to aot and passed set to the boolean true. The supplied examples implement that contract. A custom application supplies its own meaningful self-test. Failed verification writes passed false and the error to its report, replacing any earlier success. Supply -CrtDirectory when the project-local Microsoft x64 CRT archive is unavailable. Packages are evaluation ZIPs, not signed installers.

The manifest records the native ABI, Git commit, whether source files were modified, tool versions and hashes of source files and shipped files. It includes the application entry file even if that file is ignored by Git or outside the SDK repository. Such an entry is marked as uncommitted source. The included release instructions use the chosen executable filename. Keep the manifest with a result. Use verify_package.ps1 -ReportPath to retain separate verification reports for different packages.

## Verification status

The [MVP release-candidate record](../reports/mvp/README.md) contains the latest committed-source package and acceptance result. Run `./tool/verify_mvp.ps1` for the full local release gate. Its source hash covers repository source files and the application entry; when packaging an application outside this repository, retain that application's own revision and dependency sources separately.

Run the SDK checks after building the native library:

```powershell
./tool/check.ps1
dart run tool/verify_watchlist_ui.dart
dart run tool/verify_watchlist_stability.dart
dart run tool/verify_watchlist_reload.dart
dart run tool/verify_dev_launcher.dart
dart run tool/verify_dev_failures.dart
./tool/package.ps1
./tool/verify_package.ps1
```

See [the SDK milestone record](../reports/sdk/README.md). Automated checks cover native input/navigation, dataset transactions, the live watchlist's posted mouse/character messages, state-preserving code reload, AOT launch and 125% DPI. Posted messages are not IME composition or physical input-to-present measurements.

[Clean-machine and manual IME checks](windows-release-checks.md) remain explicit release gates. The current computer has only the US English input method, and no available Windows Sandbox/VM launcher was found. Multi-monitor DPI movement, human interaction and clean Windows dependency closure have not been established here.
