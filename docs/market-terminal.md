# Market terminal milestone

Design baseline: `e5345e5`. This work order is committed before implementation.
The snapshot/dataset architecture, one-window lifecycle and toolkit versions stay
in place. Each control family has its own implementation and verification commit.

## Application

`example/terminal/` evolves Market watch into a single-window terminal. The
existing Watchlist and Preferences examples remain regression fixtures.

| Tab | Content and commands |
| --- | --- |
| Watchlist | Existing virtualized instruments, search, shortlist, price sorting and sample ticks. Row context commands open Instrument or toggle shortlist for that stable record. |
| Instrument | Selected symbol and company, a line chart of sample closing prices and a bar chart of sample volumes. A radio group selects a bounded recent-history view. Empty selection has an explicit explanation. |
| Settings | Light/dark selection and an optional custom accent palette. An editable display name demonstrates mounted input retention and application draft ownership. |

All records are fictitious and kept in memory. There is no market feed or trading
connection. The default instrument dataset has 1,000 records; the verifier also
uses 100,000. History is a separate bounded dataset, replaced when the selected
instrument changes. Both charts share it and filter through the existing view
contract. Their descriptions contain dataset references, not per-point callbacks.

The menu bar has Terminal, View and Data menus. Commands navigate between tabs,
open Settings, close the window, simulate a price tick and toggle the shortlist.
On macOS they live in the native application menu and use Command shortcuts,
including Command-comma for Settings and Command-Q for quit. Windows/Linux use
Kit's in-window application menu bar and Control shortcuts. Menu dispatch emits
application actions over the existing asynchronous event channel. The application
owns their effects. Only the owned terminal window closes on Quit.

## Track 1: theme as snapshot data

`UiTheme` selects `light` or `dark` and an optional map of overrides. The map uses
the existing closed set of 16 `ThemeToken` names and opaque `#RRGGBB` values.
It cannot contain references, gradients, styles, URLs, scripts, fonts or assets.
Unknown tokens, malformed colors and more than 16 overrides are rejected before
application. An omitted theme means the built-in light theme, matching Kit init.

The theme belongs to the whole snapshot. `open`/`publish` accept a value;
`openView` accepts a theme builder that is evaluated again by rebuild/reload.
Omitting an override in the next descriptor restores its built-in value. Native
applies a changed descriptor on the UI thread after snapshot validation, before
acknowledging it. A descriptor equal to the previous one does not refresh themes.
Mounted entities, input text/selection, table scroll/selection and datasets survive.
The one-host constraint makes Kit's app-global theme compatible with this scope.

Use `Theme::change` to select/reset the palette, followed by `Theme::update` to
apply color overrides. The pinned source documents that direct `global_mut`
writes leave renderable tokens and the Base projection stale. Diagnostics expose
the descriptor and resolved colors for checks. Numeric contrast checks cover the
terminal's declared foreground/background pairs. They do not establish rendered
contrast, readability, occlusion, physical display behavior or arbitrary-user-theme
accessibility. Platform accessibility trees generally do not expose paint colors.

## Track 2: navigation controls

### Tabs

`UiTabs` is a navigation strip with 1..32 stable choices, an explicit selected
choice and optional disabled choices. Each choice has an ID of 1..256 UTF-8 bytes
and a label of 1..1024 bytes. IDs are unique within the strip. Selection must name
an enabled choice. `tab_change` reports the node ID, choice ID and source revision.
The application publishes its accepted selection and the chosen body separately.

The pinned Base Tab supplies pointer and semantics behavior, but explicitly lacks
compound keyboard navigation. The binding owns retained focus handles by choice
ID and one tab stop per strip. Left/Right and Home/End move among enabled choices;
Enter/Space activates. Focus and selection are distinct. Unrelated publications
and reorder preserve surviving focus handles. Removal/disable chooses an enabled
fallback. Roles are TabList/Tab with selected, disabled and position metadata.

Inactive bodies unmount. This does not introduce a second retention lifetime.
The terminal keeps drafts and navigation state in its application object; it
does not claim native input entities survive removal and later recreation.

### Menu bar and table context menus

Snapshot-level `UiMenu` descriptions contain stable IDs, bounded labels, action
names, checked/disabled flags and separators. Limit the initial contract to 8
top-level menus and 64 entries each, with no arbitrary submenu recursion. Menu
entry IDs are unique within their parent. Menu action names contain 1..256 UTF-8 bytes and reference a global
action binding. Global key bindings and menu entries dispatch the same
application action. Scoped text shortcuts retain their existing precedence.

Use GPUI's real `Menu`/`MenuItem` and Kit's app-menu integration. Register a typed
native action carrying a bounded command identity; resolve it against the current
description before emitting an event. Stale/disabled/removed entries cannot fire
an action. Updating menu descriptions must not accumulate key bindings or handlers.
Native macOS menu verification must query the application's AX menu bar, not a
synthetic duplicate in the content tree. Failure to observe it remains a failure.

`UiTable` may declare a bounded flat row context menu. Right-click and a keyboard
context-menu path target a stable record. Record identity is captured when opening;
dispatch resolves that identity against the live dataset and reports dataset ID,
current revision and record ID. Sorting cannot retarget an open menu by row index.
Removed/replaced table or dataset invalidates its menu; disabled entries are inert.
Legacy datasets without stable IDs cannot opt into row context menus.

Popup menus use Kit's focus, arrow navigation, Enter activation, Escape dismissal,
and focus restoration. Tests check real menu roles/actions and the event effect.
Native macOS application menus and content popup menus are separate mechanisms.

### Tooltips

The terminal's refresh and navigation buttons have bounded help text. The initial
API is an optional `tooltip` on `UiButton`, at most 1,024 UTF-8 bytes. Use Kit's
tooltip on hover and expose the same help on the control's semantic description
so keyboard/assistive clients can obtain it without pointer hover. A tooltip is
not the accessible name and cannot contain arbitrary content or actions. Check
hover appearance/dismissal through GPUI and help text through external clients.

### Radio groups

`UiRadioGroup` has 1..32 stable labeled options, selected ID, disabled state and
optional disabled choices. It emits `radio_change` requests. Native owns retained
focus by option ID; the application owns selection. One tab stop, arrow/Home/End
navigation among enabled options, Space activation, and native RadioGroup/RadioButton
roles are acceptance criteria. Snapshot retention, reorder, disable and removal
are tested. Tabs and radios share validated choice data, not a public generic
control that hides their different semantics.

## Track 3: dataset charts

`UiChart` supports only `line` and `bar`, one series per node. It references a
dataset, an x-label column, a finite numeric value column, and an optional existing
`TableView`. Bounds are 1..512 points, a fixed maximum series magnitude, and bounded
height. The terminal uses separate price and volume nodes. No arbitrary Dart or
native application callbacks, custom paint programs, live animations, pie charts,
candlesticks, multi-axis charts or streaming policy are added.

Validate references and columns with the snapshot and dataset transaction. Cache
the projected series by dataset/view revisions; an unrelated snapshot must not
re-encode or republish records. A bounded recent tail is explicit when the filtered
view exceeds the point limit. Do not silently replace missing/non-numeric values
with zero. Define invalid-value rejection or an explicit reported omitted count
before implementation tests; the terminal's own history must contain valid values.
Use Kit LineChart/BarChart for drawing. View projection and text alternatives read
the same series. An empty view produces an empty-state description.

Chart semantics include a named chart, series kind, point count, first/last values,
range, and bounded point text alternatives with stable record IDs. Charts are
read-only in this milestone. Programmatic alternatives establish data agreement,
not visual graph quality or human screen-reader usability.

## Verification and delivery

1. Commit this design and source spike findings.
2. Theme codec/bounds and native palette/reset/state-retention checks. Commit.
3. Tabs, menu bar, context menus, tooltips, radios. One checked commit per family,
   including Dart wire/events, native validation/headless interaction and semantics.
4. Charts with numeric/bounds/view/record identity tests, actual Kit rendering and
   dataset-edit/empty-view behavior. Commit.
5. Terminal assembly and portable interaction, external accessibility and actual
   code-reload verifiers. Theme choice, selected tab and app draft survive reload.
6. Windows UIA locally; Linux X11 AT-SPI and macOS AX in hosted CI. Extend the
   accessibility workflow. Keep Settings, Watchlist and 100k JIT/AOT smokes green.
7. Retain failures, exact source/build identities, platform observations and limits
   under `reports/market-terminal/`. Update README, SDK and roadmap. Require green
   final-tip CI and a clean pushed tree before claiming completion.

Human visual/screen-reader sessions, physical hardware/IME checks, signing and the
historical reload disposition remain parked. No presentation-latency or performance
advantage claims follow from these correctness tests. Editor bindings, general
virtual lists and additional chart/control families remain separate milestones.

### Theme implementation note

Custom overrides use Kit's configuration resolver, then synchronize Component
and Base. Overriding primary/secondary/status backgrounds recalculates their
hover/active fallbacks. Explicit component-specific colors in the built-in theme
remain in effect; this is not an exposure of Kit's full theme-file schema.

### Row context-menu implementation note

The host captures identity before Kit's deferred row-index hook could be affected
by another view update. It owns one PopupMenu session for pointer and Shift+F10
entry paths. Keyboard opening anchors at the window center; pointer opening uses
the click position. Sort/filter changes leave the captured record valid while it
remains in the dataset generation, even if the filter hides it. Dataset
replacement, table removal/rebinding or changed menu entries cancel the session.
