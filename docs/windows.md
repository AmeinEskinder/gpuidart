# Secondary windows

A host owns one process-wide GPUI application. The window it opens at startup
is the main window; `openWindow` adds secondary windows to the same
application, each with its own description, datasets and native entities.

```dart
final host = await GpuiHost.open(mainRoot, datasets: [records]);
final inspector = await host.openWindow(
  UiColumn('root', [const UiText('title', 'Inspector')]),
  options: const GpuiWindowOptions(title: 'Inspector', width: 480, height: 360),
  datasets: [details],
);
inspector.events.listen((event) => print('${event.type} in ${event.window}'));
await inspector.publish(UiColumn('root', [const UiText('title', 'Updated')]));
await inspector.close();
```

## Contract

| API | Contract |
| --- | --- |
| `openWindow(root, {options, datasets, actions})` | Opens a window with an initial description, optional datasets and actions. Completes once native has opened the window. Window IDs start at 1; the main window is 0. |
| `GpuiWindow.publish` | Publishes to that window with the same operation-or-snapshot rules as the host, with its own revision sequence. |
| `GpuiWindow.events` | The host's event stream filtered to that window; `GpuiEvent.window` carries the ID on every event. The host stream still delivers every window's events. |
| `GpuiWindow.diagnose`, `readInput`, `writeInput` | Inspection and controlled-input commands addressed to that window. |
| `GpuiWindow.registerDataset` | Registers a dataset with that window. Edits, replacements and release go through the host, which routes them to the dataset's window. |
| `GpuiWindow.close` / `done` | Close is idempotent and asks native to close the window; `done` completes when native reports the window closed, whether by close or by the user. |

Rules:

- Dataset IDs are unique across the host. A dataset belongs to the window
  that registered it, and the host routes its transactions there.
- Closing the main window closes the application, and every secondary window
  with it. Closing a secondary window leaves the application running.
- When a window closes, its pending publications and requests settle with a
  `StateError`, its datasets are released, and later calls throw.
- Commands that reach native for a window it no longer holds are rejected
  asynchronously with `Unknown window`.
- Publication tracing covers the main window; secondary windows publish
  without trace records.

## Wire

Secondary windows use window-addressed exports beside the existing ones:
`gd_window_open(host, bytes, len)` with `{"request", "id", "initial"}` where
`initial` is the same object `gd_create` takes; `gd_window_close(host, id)`;
and `gd_window_publish`, `gd_window_update`, `gd_window_dataset`,
`gd_window_diagnostic` and `gd_window_input`, each `(host, id, bytes, len)`
with the payloads of their unaddressed counterparts. Statuses match the
unaddressed functions.

Native tags every event from a secondary window with `"window": id`. Three
events describe the window itself: `window_opened {request, window}`,
`window_rejected {request, window, message}` and `window_closed {window}`.
A library without these exports makes `openWindow` throw a `StateError`.
