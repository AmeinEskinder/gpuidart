# Native platform probe

This standalone Rust executable supplies the external accessibility clients used
by the Dart verification drivers. Its own Cargo lockfile keeps these tooling
dependencies separate from the SDK's GPUI workspace.

Build from the repository root with `dart run tool/native_probe/build.dart`.
The Dart drivers also build it once before first use. Cargo checks source and
dependency freshness on every driver run. Linux requires `libatspi2.0-dev` and
`libglib2.0-dev`. Windows requires the Windows SDK and C++ linker. macOS links the
system ApplicationServices, CoreFoundation, CoreGraphics and Metal frameworks.

The binary is `build/native-probe/debug/gpuidart-native-probe`, with `.exe` on
Windows. Commands are:

```text
accessibility PID OP NAME VALUE ID
cache-events PID OUTPUT     (Linux)
environment                 (Windows)
metal                       (macOS)
```

`OP` is `query`, `invoke`, `invoke-menu`, `toggle`, `select`, `set-value`,
`set-range`, `focus` or `hover`. Pass empty strings for unused name, value and ID
arguments. Actions require exactly one matching element. An ID takes precedence
over a name. The clients use the OS APIs to perform actions and read properties;
the Dart tests then verify application state and the externally observed result.

Windows uses native IUIAutomation, including FullDescription, supported control
patterns and physical pointer movement. Its tree can also include native title
bar controls that the former managed UIA client did not enumerate. Existing
application node properties and pattern names keep the same report schema.
An unavailable element during a query uses the same bounded status-75 restart
contract as Linux. Actions and other COM failures are not retried.

Linux uses libatspi with its original timeouts. A known stale object during a
query exits with status 75, and the Dart driver retries the complete query in a
fresh process at most four times within its deadline. APPLICATION_GONE qualifies
only if the application root still answers an uncached AccessibleId read.
The GIO cache monitor subscribes on the accessibility bus, confirms the sender's
PID, checks actual GVariant argument signatures and waits for both addition and
removal signals. It creates its report exclusively and records failures.

macOS requires Accessibility authorization. It reads AX attributes and actions,
including the application menu bar. Invalid-element reads restart discovery up
to four times, including target discovery before an action. The typed stale-read
error is emitted only before sending the action. Failed action calls are never
replayed. Permission denial is an error, and every traversal has a 4,096-element
bound.

The platform declarations follow the public
[GNOME libatspi API](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/),
[GIO D-Bus API](https://docs.gtk.org/gio/class.DBusConnection.html),
[Apple AX API](https://developer.apple.com/documentation/applicationservices/axuielement),
and [Windows UI Automation API](https://learn.microsoft.com/en-us/windows/win32/winauto/entry-uiauto-win32).
Cross-target `cargo check` verifies Rust types; live platform workflows remain
the gate for native linking, authorization, protocol behavior and UI actions.
