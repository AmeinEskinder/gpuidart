# Desktop SDK preview

GPUI-Dart 0.1 is a desktop SDK preview with Windows x64, macOS 15 ARM64 and Ubuntu 24.04 x64/X11 implementations. See the [acceptance matrix](../reports/cross-platform/status.md) for verified environments and remaining gates. Windows DPI setup requires Windows 10 version 1803 or later, using Microsoft's [process DPI-context API](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiawarenesscontextforprocess); the local reference was tested on Windows 11. The application model is one host with a main window and optional [secondary windows](windows.md), immutable UI descriptions, and retained native controls and datasets. The JSON wire format and diagnostic commands are internal. Build the Dart package, native library and launcher from the same revision.

The Dart host checks native ABI/protocol version 1 before creating a host. Libraries without a matching version fail with a rebuild instruction. macOS additionally requires companion lifecycle extension version 2 and the matching `gpuidart-launcher`. The native library rejects a second active host, including callers from another Dart isolate. Await successful completion of the previous host's done Future before opening another one. A shutdown timeout requires process recovery if the native runner remains stuck.

## Run the representative screen

From the repository root:

```powershell
./tool/build.ps1
dart run tool/dev.dart
```

On macOS/Linux, use `dart run tool/build.dart` in place of the PowerShell build command. Linux currently requires X11; see [Unix prerequisites and packaging](unix-release-checks.md). The application API and development entry point are the same on all three targets.

The default entry point is [Market watch](../example/watchlist/main.dart). It contains 1,000 fictitious instruments, search, row selection, a shortlist, price sorting and sample price updates. Search and the shortlist toggle are a native view over the dataset; updating a price or shortlist entry sends one cell edit. There is no live feed or trading connection. Application data is in memory and resets when the process exits.

Select a row, add it to the shortlist, simulate a price update, and switch to the shortlist. Editing the search changes the native table view without republishing its records. Selection follows stable record IDs; if filtering removes the selected record, selection clears. Ordinary view rebuilds and code reload preserve mounted native entities.

The [Preferences example](../example/settings/README.md) exercises checkboxes,
selects, sliders, confirmation dialogs and controlled text. Run it with
`dart run tool/dev.dart example/settings/main.dart`. Its draft and saved values
are in memory for the session. It handles conflicting input writes and leaves
native composition authoritative.

For another entry point:

```powershell
dart run tool/dev.dart example/main.dart
dart run tool/dev.dart path/to/main.dart --your-app-argument
```

Run the launcher from the project root. It watches the entry point's directory recursively and the package's lib directory. It reports compilation/reload errors and keeps the previous running code on a rejected reload. Rust changes and Dart changes that the VM cannot reload require a restart. Close the application window to stop the launcher.

Startup waits at most 30 seconds for reload registration. Failed startup cleans up the launched process tree, including Dart's VM child process. Ctrl+C requests application shutdown. Reload service calls also have a timeout, so an unavailable application does not leave the launcher waiting indefinitely.

Windows and Linux execute GPUI inside the blocking native runner isolate. macOS starts an owned native companion because AppKit needs the process main thread and its normal quit terminates that process. Dart creates and reaps the child; close waits for transport completion and child exit before disposing callbacks. The companion uses a private Unix socket with bounded frames and queues. It adds process/transport cost; Windows measurements do not quantify that cost.

The [market terminal](../example/terminal/README.md) adds Watchlist / Instrument /
Settings navigation, real app menus, record context menus, themes and dataset
charts. Run `dart run tool/dev.dart example/terminal/main.dart`. Its data is
fictitious and stays in memory. The [navigation and charts contract](navigation-and-charts.md)
defines the bounded public API and event ownership.

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
  try {
    await host.close();
  } finally {
    await subscription.cancel();
  }
}
```

Put the application object outside its build method. Register its existing build method with openView; rebuild executes that method and publishes the result, as [operations against the previous tree](retained-tree.md) when the host can compute them and as the whole description otherwise. registerGpuiReload supplies the development launcher's reassemble/close extensions and does nothing in product AOT builds. Reload does not rerun main or field initializers.

Serialise asynchronous UI handlers that touch the same dataset. The watchlist's event queue is an example. Every dataset transaction must finish before the next one begins. Surface failures to the application; do not discard publication Futures. Stop timers/subscriptions during shutdown, and await close or done before exiting.

## Public contract

| API | Contract |
| --- | --- |
| UiColumn / UiRow | Vertical/horizontal groups with the native theme's standard spacing. Rows wrap when space is limited. The screen scrolls vertically when its content exceeds the window. A child style's `flex` shares the remaining space; `minWidth`, `maxWidth`, `minHeight` and `maxHeight` bound any node. |
| UiStyle.cached | Keeps a container's rendered native subtree across frames until a change inside it, a dataset it shows or a whole publication touches it. Needs a fixed pixel height. See [retained tree](retained-tree.md#cached-subtrees). |
| UiStack | Children overlap in order. A child sits at the top left with its own size unless its style has an `inset` from the stack's edges; `full` width and height cover the stack. Size the stack through its style or a flex parent. |
| UiScroll | A bounded vertical, horizontal or two-axis scroll container with a native scrollbar. Its offset is retained by ID across publications and reload. |
| UiTree | A tree of `UiTreeItem`s (stable IDs, labels, optional children, `expanded`, `disabled`) with one `selected` item. A click selects and toggles a folder: `tree_select` carries `GpuiEvent.item`, `tree_expand` adds `GpuiEvent.expanded`. A publication whose items or selection differ is authoritative; a repeated one leaves the user's state alone. At most 4,096 items, 32 deep. |
| UiPopover | A labelled button that opens an anchored popup holding its children. Native owns the open state unless `open` is published; `popover_change` reports each change in `GpuiEvent.open`. |
| UiSheet | A sheet from one window edge (`placement`, `size`) with a title and its children as content, shown while `open` is true; one per window. Closing it natively emits `sheet_close`, and the application publishes it closed. |
| UiRichText | Markdown rendered natively (headings, emphasis, lists, links, code, tables) from at most 64 KiB of source; `selectable` allows selection and copying. Display only. |
| UiPanes | Children as resizable panes on one axis with native drag handles; each `UiPane` gives an initial size and bounds in logical pixels. Dragged sizes are retained by ID; a publication that changes a size resizes that pane; `panes_resize` carries every size in `GpuiEvent.sizes`. Size the group through its style or a flex parent. |
| UiText / UiButton | Text and native button. Click events carry node ID and snapshot revision. |
| UiInput | Native-retained by default. `controlled: true` enables guarded text/selection writes; native remains authoritative during composition. See [controlled inputs](controlled-inputs.md). |
| UiCheckbox / UiSwitch / UiSlider / UiSelect | `UiSelect(searchable: true)` is a combobox whose open list filters its options as the user types. Application values with native change-request events (`checkbox_change`, `switch_change`, `slider_change`, `select_change`). The control shows the interaction immediately; the next publication's value is authoritative, so publish the accepted value. See the [settings controls contract](control-catalog.md). |
| UiProgress / UiSeparator | A determinate or indeterminate progress bar; a horizontal or vertical rule with an optional label. Display only. |
| UiDatePicker | A calendar picker holding one `YYYY-MM-DD` date or none, with a placeholder and disabled flag; `date_change` carries the nullable requested `date` and the next publication is authoritative. |
| UiIcon | A Lucide icon from the bundled catalog by name (`search`, `chevron-down`), with an optional size and theme-token or hex color. Native rejects names outside the catalog. Display only. |
| UiImage | A raster or SVG image from a file path (by extension) or inline bytes with an explicit format, fitted into its bounds (`contain`, `cover`, `fill`, `scaleDown`, `none`) with optional width and height. Inline bytes are decoded once per node and content. Display only. |
| UiMenuButton | A button that opens a popup menu of the same `UiMenuEntry` items application menus take; choosing an action entry emits its global action, so the entry needs a global `UiAction` binding. |
| pickPaths / pickSavePath / openUrl / revealPath | Native file and folder choosers, the OS save dialog, the OS URL handler (http, https and mailto only) and the file manager, through the host's request channel. Dialogs resolve when they close; a cancelled dialog resolves to null. Not covered by headless tests. |
| UiCanvas | A retained draw list (rectangles, circles, lines, polylines) painted natively inside the node's bounds; the list travels as node fields, so a change sends only that node. See [canvas and animation](canvas-animation.md). |
| UiStyle.animation | A native timeline over a node's opacity or offset with a duration, easing and optional repeat. GPUI interpolates every frame; Dart publishes nothing while it runs. |
| UiConfirmDialog | Native confirmation modal with one result, focus trapping and cancellation when its trigger is removed or disabled. |
| UiSemantics | Optional bounded names and compatible roles on every node; native controls supply their states. See [accessibility and platform gaps](accessibility.md). |
| UiTable | References a registered dataset ID. Cells contain strings and render in Rust. |
| UiList | A virtualized list over one column of a dataset with record IDs, in an optional filter/sort view; `list_select` carries the chosen record in `GpuiEvent.listSelection`, the item shows the pick at once and the next publication's `selected` is authoritative. See [datasets](datasets.md#lists). |
| GpuiWindowOptions | Initial title and logical width/height. Width 320..8192, height 240..8192. Window sizing is independent of display scale. |
| GpuiEvent.tableSelection | Typed row-selection data with table ID, dataset ID and dataset revision. Ignore an index from a revision that the application no longer holds. |
| GpuiEvent.tableView / viewsSettled | A table's view index landed: over 10,000 records the index computes off the frame thread after the acknowledgement, and `viewsSettled` completes when no table is waiting for one. See [table views](datasets.md#table-views). |
| Repaint on update (Windows) | After a publication, an operation update or a dataset update has been applied to a window that has been idle for a frame interval, the host asks Windows to repaint it at once instead of at the next vsync tick; see [frame scheduling on Windows](#frame-scheduling-on-windows). |
| publish / rebuild | Completes after native applies the description, sent as operations against the previous publication when possible. Subtrees handed back as the same `UiNode` instances (const nodes, `UiMemo`) are neither re-described nor re-diffed. This is not a presentation fence. |
| UiMemo | Keeps a built subtree while its inputs compare equal, so a rebuild reuses it by identity. See [retained tree](retained-tree.md). |
| patch | Writes one published node's own fields as a single `set` operation, with no build, describe or diff; the node keeps its ID and kind and carries no children. The write stands until the next publication, which carries the application's value. |
| registerDataset / editDataset / replaceDataset / releaseDataset | Revisioned transactions; Dart data commits after native acknowledgement. Edit batches change cells and rows, and insert, delete or move records in order. See [datasets](datasets.md). |
| TableDataset.generated | Records produced on demand by a generator and uploaded slice by slice from a short-lived helper isolate, so the calling isolate never holds them; the path for a million records. See [datasets](datasets.md#operations-and-lifetime). |
| openWindow / GpuiWindow | A secondary native window with its own description, datasets and revision sequence; events carry `GpuiEvent.window`. Closing the main window closes the application. See [secondary windows](windows.md). |
| UiTheme | Whole-snapshot light/dark palette plus bounded opaque token overrides. `openView` reevaluates its theme builder on rebuild/reload. |
| UiTabs / UiRadioGroup | Controlled option IDs with retained focus and keyboard navigation. Changes return on the event channel. |
| UiMenu / UiMenuAction | Flat app menus referencing global actions; native menu bar on macOS, Kit menu bar on Windows/Linux. |
| UiTable.contextMenu | Record-bound row commands, pointer or Shift+F10 activation, typed RowActionEvent. Requires stable row IDs. |
| UiButton.tooltip | Bounded help text with native hover behavior and accessible description. |
| UiChart | Read-only line/bar series from a retained dataset/view, at most 512 projected points. |
| close / done | Close is idempotent. Normal completion follows native teardown. Failure can precede teardown on a shutdown timeout; native memory stays alive until the runner returns. Pending requests settle with success or an error. A paused event subscriber does not delay done. |

Node IDs are nonempty and unique across the whole description, including nested rows. Reusing an ID and control kind preserves its native state. Removing the node releases its retained entity. Changing a table's dataset or replacing a dataset resets selection and scroll. Row indices are not stable record identities; the watchlist keeps an instrument symbol in application state.

Snapshots have at most 4,096 nodes, depth 32 and 16 MiB encoded size; an operation update carries at most 4,096 operations and its result meets the same bounds. Datasets have at most 1,000,000 rows and 64 columns; records beyond one message upload in appended slices. The native command queue has 64 slots. Invalid descriptions, stale revisions, a full/closed queue and overlapping transactions are errors. Await or handle the returned Future.

Native acknowledgements have a 30-second deadline; shutdown reporting has a 10-second deadline. Configure these with `requestTimeout` and `shutdownTimeout` when opening the host. Missing acknowledgements, malformed events and caught native panics close the host and settle pending requests. See [failure handling and its limits](failures.md).

## Frame scheduling on Windows

GPUI draws a window that has changed at the next vsync tick. For an update
the application sends in answer to an input, that tick is up to a frame
away from the moment the change is applied: the traced click chain of the
comparison benchmark measured 8 ms at the median and 15 ms at the 95th
percentile between an edit applied natively and its frame, against a
0.3 ms round trip through Dart. On Windows the host therefore asks the
window to repaint as soon as a publication, an operation update or a
dataset update has been applied (`RedrawWindow` with an invalidation, the
same request the vsync tick makes), at most once every 4 ms, unless the
window is presenting at a frame cadence, which is what a burst of updates
or a stream painting at every tick looks like, and where the extra frame
would be rendered for nothing. The cadence is read from the window's own
last three presents, so no refresh rate is assumed: the longer gap between
them is the interval, it counts as a cadence up to 50 ms, and the window
is in it while its newest present is younger than that interval and a
half. A lone frame just before the update, the hover or the press of the
click itself, does not hold the repaint back, so a click on a quiet window
gets the early frame, and each window is judged by its own presents.

Why the idle condition: measured on the comparison fixture with six runs a
side ([the click tail](../reports/comparison/click-tail-20260930.md)), an
unconditional repaint took a click's changed frame to the display 19 ms
sooner at the median on a click every 200 ms, but on a burst of thirty
clicks a second it rendered one present per click that the display never
took (about 890 presents in ten seconds against 600 on a 60 Hz display),
since the tick was painting every frame anyway. With the cadence rule the
same two workloads, six runs a side in one sitting, read: on the click
workload the repaint fired on every one of 300 clicks and the changed
frame reached the display 12 ms sooner at the median (31.6 ms against 43.4)
and 11 ms sooner at the 95th percentile (37.6 against 48.2), with one
present per click; on the burst the window made 598 presents in ten
seconds against 597 with the repaint off.

The vsync tick itself is paced on Windows (a patch to the vendored
platform, [frame-pacing.patch](../native/vendor/frame-pacing.patch)): the
tick waits until the next vertical blank less a margin for the compositor
less the recent 99th percentile of the draw time before it invalidates the
window, so a frame drawn at the tick is presented late in the refresh
interval, carries input up to that later moment, and reaches the display
at the same blank it would have. Unpaced, the window presented 4 to 5 ms
after the blank and waited 28 to 29 ms for the display; paced with the default 5 ms
margin it presents 9 to 10 ms after the blank and waits 23 to 24, and input
reaches the display 5 to 6 ms sooner at the median on the burst and scroll
workloads (six runs a side).
`GPUI_FRAME_PACING=0` turns the pacing off.

`GPUIDART_DRAW_ON_UPDATE=0` in the process environment turns the repaint
off, which is the behavior on macOS and Linux; `GPUIDART_DRAW_ON_UPDATE=always`
fires it after every update regardless of idleness, for measurement. The
setting is read once at startup.

## Package an AOT application

The following commands describe the Windows package. For macOS/Linux use `dart run tool/package.dart --name=MyApp --entry=path/to/main.dart`, then `dart run tool/verify_package.dart ARCHIVE REPORT.json`. Their [release guide](unix-release-checks.md) describes the bundle, standalone verifier, runtime prerequisites and signing limits.

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

The package verifier expects a --self-test mode that exits successfully and prints one JSON object with mode set to aot and passed set to the boolean true. The counter and watchlist examples implement that contract. Preferences has a separate `tool/verify_settings.dart` JIT/AOT verifier. A custom application supplies its own meaningful self-test. Failed package verification writes passed false and the error to its report, replacing any earlier success. Supply -CrtDirectory when the project-local Microsoft x64 CRT archive is unavailable. Packages are evaluation ZIPs, not signed installers.

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
dart run tool/verify_settings.dart build/settings-check.json
./tool/package.ps1
./tool/verify_package.ps1
```

See [the SDK milestone record](../reports/sdk/README.md). Automated checks cover native input/navigation, dataset transactions, the live watchlist's posted mouse/character messages, state-preserving code reload, AOT launch and 125% DPI. Posted messages are not IME composition or physical input-to-present measurements.

The [settings milestone](../reports/control-catalog/README.md) records per-control
validation, headless interaction, Dart wire and live-window checks. Its driver
uses GPUI keyboard dispatch, observes focus restoration after the dialog closes,
and checks both native values and application state. The current
[schema decision](protocol-schema-decision.md) keeps manual codecs and semantic
tests; internal wire formats are not a supported external API.

[Release evidence](../reports/release/README.md) records clean Windows Sandbox and Linux desktop VM launches. [Windows Japanese IME observation](../reports/ime/windows-japanese-20260926/README.md) passed at 125% scale. [Linux Japanese XIM observation](../reports/ime/linux-japanese-20260926/README.md) passed with configured Fcitx5/Mozc on Xorg; see the required setting in [Unix release checks](unix-release-checks.md#japanese-input-with-fcitx5-on-x11). Both include real composition, screenshots and reload while composing. The owner authorized agent observation; no independent human observer participated. Other input backends and physical mixed-monitor behavior remain unverified. The [reload observation](../reports/mvp/attempt-023eef4/README.md) also remains unlocalized despite subsequent passing checks. The SDK uses the [MIT License](../LICENSE); dependencies retain their own terms.
