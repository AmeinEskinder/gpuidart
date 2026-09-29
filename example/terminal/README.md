# Market terminal

One window with Watchlist, Instrument and Settings pages. All prices and volume
are fictitious; the example has no network connection, trading or durable storage.

Build the native host, then run from the repository root:

```sh
dart run tool/dev.dart example/terminal/main.dart
```

The window is two resizable panes: a navigation tree (the three pages and a
Help folder whose "Keyboard shortcuts" item opens a sheet of rich text) and
the page content. Watchlist splits again into the instrument table and a
notes pane that renders the selected instrument as markdown, with a Find
popover holding a searchable select that jumps to a symbol.

Watchlist starts with 1,000 instruments. Search symbols, sort prices, select a
record and simulate a price tick. Right-click a row or focus the table and press
Shift+F10 for record commands. Open Instrument to see line and bar charts of that
record's sample history. The range radio group selects 20 or 48 observations
without republishing history. Button tooltips explain the toolbar actions.

Settings edits an in-memory name and selects light/dark palettes plus a custom
accent. The app saves controlled input drafts before unmounting a page and restores
them when returning. Native entities retain state while mounted; tab remounts
create new native inputs. Navigation waits while an input is composing.

The Terminal, View and Data menus dispatch the same global actions as shortcuts.
macOS uses the native application menu bar; Windows/Linux use Kit's menu bar in
the window. Use Command on macOS and Control elsewhere:

| Shortcut | Action |
| --- | --- |
| modifier+1 / modifier+2 | Watchlist / Instrument |
| modifier+, | Settings |
| modifier+F | Search |
| modifier+R | Simulate a price tick |
| modifier+B | Toggle selected record's shortlist flag |
| modifier+Q | Close |

Change `TerminalApplication.heading` in `app.dart` during a development session
to exercise code reload. Theme, application drafts and datasets are fields on the
live application object; reload does not rerun initializers.

## Verification

These commands refuse to overwrite their reports:

```sh
dart run tool/verify_terminal.dart build/terminal.json --semantics
dart run tool/verify_terminal_reload.dart build/terminal-reload.json
```

The default verifier uses 100,000 source records. `--rows=1000` selects a smaller
fixture. The semantics track requires the platform client described in
[accessibility verification](../../docs/accessibility.md); macOS needs its compiled
AX probe and Linux needs an enabled accessibility bus in an X11 session. Hosted
CI supplies these prerequisites. The AOT verifier runs the same interaction
sequence; it is compiled separately from the example's launcher.

See [evidence and current failures](../../reports/market-terminal/README.md).
Programmatic interaction and OS tree queries do not establish visual quality,
screen-reader usability or presentation latency.
