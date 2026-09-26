# Accessibility milestone: progress and evidence

The milestone is **in progress**. These are feasibility and wire-contract results,
not complete SDK accessibility acceptance or human screen-reader verification.

## Platform spike (`a103da1`)

[Hosted run 36270561107](https://github.com/AmeinEskinder/gpuidart/actions/runs/36270561107)
passed on Windows 2022, macOS 15 ARM64 and Ubuntu 24.04 X11/Xvfb. Each external
client queried the settings window, invoked Appearance using a platform action,
and observed the application change section. Raw responses are retained beside
this report. Local Windows evidence is `windows-spike-1.json`.

| Platform | Actual client | Result scope |
| --- | --- | --- |
| Windows | `System.Windows.Automation` | UIA query and InvokePattern |
| Linux | GI Atspi, session D-Bus | AT-SPI query and action |
| macOS | `AXUIElement`, companion PID | External AX query and AXPress; trust check passed |

No internal inspect payload supplied the roles, names or values. Inspect only
located the native PID. Queries expose existing Kit behavior: named buttons,
checkbox state and input value; the select and slider are unnamed. Text labels
are missing. Slider SetValue effects and disabled action behavior still need
verification; source has only Increment/Decrement handlers without disabled guards.

The Linux runner enables accessibility only inside its disposable D-Bus session.
The macOS probe does not modify TCC, grant itself access or use provider introspection
as an external-query substitute. All clients have a 20-second process deadline
and a 4,096-node result bound. That bound is not a virtualization proof (Windows
currently enumerates before checking the bound).

## Wire model checkpoint

Optional `UiSemantics` / Rust `Semantics` carry a bounded label, compatible role
and heading level. Existing native control properties remain the source of values
and states. This checkpoint does **not** yet apply annotations to rendered controls.
The field matrix and reasons for rejecting independent state overrides are in
`docs/accessibility.md`.

Local checks: 55 native tests passed (including 2 new semantics tests), 3 new Dart
semantics tests passed, analyzer clean; 3 snapshot-experiment tests passed after
the Node structure change. No timing/performance claim is made.

Retained implementation failures: the first source-edit helper used Windows'
default text encoding and stopped on a UTF-8 test fixture; no test data was lost.
The initial build then reported missing `semantics` fields in existing test
literals. The helper was corrected to explicit UTF-8 and the literals updated;
native and experiment tests passed. Dart analyzer also caught an obsolete
constructor argument during removal of the unsupported description field.

## Remaining acceptance work

### Native adapter checkpoint (local Windows)

Annotations now reach real controls. Text uses AccessKit's text value (a Label's
label alone produced an empty UIA name). Tables generate column headers and
viewport rows/cells; record IDs key the row elements and author IDs. External
table verification is still pending.

The settings platform track passed all 15 steps locally in
`settings-platform-2.json`. `windows-controls-5.json` passed nine external action
steps: toggle, text/range writes, dialog open/cancel/confirm and resulting state.
`windows-disabled-1.json` verifies disabled flags, rejected/inert actions and a
single enabled-slider change event. The native suite has 57 passing tests.

Fixes and retained failures:

- `windows-controls-1.json` / `windows-controls-3.json`: modal absent from the
  platform tree. The binding supplied decision callbacks but no footer: at this
  pin `button_props` does not instantiate buttons. The host now provides actual
  named modal content and Confirm/Cancel buttons, retains Kit's focus trap and
  keyboard dismissal, and hides background semantics while open. Headless tests
  click both decisions and verify exactly one result event apiece.
- `windows-controls-2.json`: verifier name lookup became ambiguous after ordinary
  text labels were correctly exposed. Action clients now support author IDs and
  fixture assertions distinguish text labels from controls.
- `settings-platform-1.json`: disabled Checkbox was inert but UIA reported enabled.
  The adapter now sets the actual AccessKit disabled flag. Slider and confirmation
  trigger receive the same flag; Select needed a root metadata decorator.
- Adding test observation to the outer table collided with Kit's inner `table`
  observation ID in three existing tests. Removed that redundant observation;
  platform table semantics remain on the outer node.
- The new headless modal pointer test initially clicked during the opening
  animation and failed in the full suite. It now waits for stable button bounds
  before a single click; all 57 tests passed together.

The pinned Slider root has neither a label setter nor SetValue behavior. The host
uses Kit's track/thumb/state beneath one focusable semantic root, with bounded
SetValue/Increment/Decrement actions on the existing event path. This preserves
native pointer/keyboard behavior; visual equivalence of the simplified presentation
has not been asserted.

The pinned Select component exposes no author-ID/disabled-metadata setters. Its
adapter decorates the actual Base root after layout using GPUI's checked element
downcast API. Two concrete output types are tied to the pin; a dependency upgrade
must update this adapter if those types change. A mismatch fails explicitly, and
headless/live tests exercise both observation-enabled and ordinary native builds.
No unsafe memory cast, parallel semantics tree or dependency-cache edit is used.

Hosted checks for the full adapter/settings track are pending at this checkpoint.

- Hosted action, disabled-state and 15-step settings platform checks.
- Watchlist platform track, generated table roles/identity and virtualization checks.
- 100k JIT/AOT and reload regression checks after adapter changes.
- All suites/platform queries green at final commit, updated public docs, clean tree.

No claims about screen readers, visual layout, hardware IME, Wayland, visible pixels
or presentation latency. Parked hardware/signing/reload-disposition gates remain parked.

## External text and table follow-up

At `4cb3582`, all four existing SDK/lifecycle workflows passed, as did the expanded
Windows accessibility job. The [accessibility run 36272919911](https://github.com/AmeinEskinder/gpuidart/actions/runs/36272919911)
retains two hosted failures (`linux-controls-1.json`, `macos-controls-1.json`).
macOS returned a Boolean checkbox value; the verifier incorrectly accepted only
numeric 1. Linux exposed no Text interface for the input: the Kit root supplied a
scalar value without the TextRun descendants required by AccessKit. The host now
adds a synthetic TextRun to the real input root using that frame's native value.
The initial checked downcast assumed Input deferred Base rendering; a headless
test caught that it renders Base immediately. The corrected adapter decorates
that actual element. Select adds a named selected-value child for AT-SPI clients,
whose pinned adapter does not export its scalar string value.

The pinned AT-SPI adapter has no EditableText interface. Linux verifiers therefore
name their GPUI diagnostic-key text writes explicitly, then query actual AT-SPI
Text. This is **not** an external AT-SPI text-write pass. Windows and macOS retain
the external value-write checks. Rich text range geometry, cursor/selection
navigation and editing through AT-SPI remain gaps.

`watchlist-platform-1.json` and `watchlist-platform-2.json` retain failed attempts
to select/invoke a row through UIA. AccessKit Windows explicitly excludes Row from
SelectionItem support; its consumer also excludes selected-state nodes from Invoke.
The binding preserves accurate Row/Cell roles and the selected flag rather than
mislabeling rows. Windows uses the existing diagnostic selection path and inspect
for selection assertions, with external UIA queries for record/cell identity and
contents. The report lists unavailable patterns. Linux/macOS attempt real row
activation against their platform adapters. Stale row actions resolve the record
against the current view before selecting.

`watchlist-platform-3.json` passes seven local Windows steps on 100,000 records:
bounded initial platform tree, actual input filtering to one native row, selection,
formatted incremental price, clear-filter retention, sort retention and removal.
Only the selection action/state use the declared diagnostic path. Dataset messages
increase by exactly one for the price edit; view changes do not republish records.
No offscreen-cell retrieval or UIA Grid/Table pattern support is claimed.

At `6d48631`, Windows platform checks pass including Watchlist. On macOS, control
actions, disabled controls and all 15 Settings steps pass. The first Watchlist
read after filtering failed with AX invalid-element: traversal held a row that
was removed by the concurrent frame update (`macos-watchlist-1.json`). The client
now restarts the whole **query** at most four times on that specific error and
records each restart. It never retries actions or accepts a partial tree. Linux
reached the new Text interface but Python GI resolved an inherited deprecated
`Accessible.get_text` overload instead of the Text method; the explicit
`Atspi.Text.get_text` call fixes that client error (`linux-text-client-1.json`).
The rendered-cell headless test now also checks Row/Cell roles and the formatted
price label; its first compile caught a missing qualified Role type, then the
selector's owned-SharedString requirement. The corrected test passes.

## Adapter mapping corrections

At `8df7e77`, Linux passes all nine control steps (declared GPUI-key text-write
path, external AT-SPI reads), but `linux-disabled-1.json` shows a disabled Confirm
button reported enabled. Source in accesskit_atspi_common grants Enabled/Sensitive
whenever read-only state is unsupported, even if disabled. macOS Settings and
disabled checks pass; `macos-watchlist-2.json` proves AXPress selected BRK0025 in the
application, but AXSelected was absent. The consumer excludes Row/Table from
item/container classification. Windows additionally excludes Row from its
SelectionItem provider. These are adapter omissions; changing SDK roles or
accepting false states would hide them.

Three narrowly patched, version-preserving AccessKit crates are now vendored;
[the complete patch and provenance](../../native/vendor/README.md) separate four
mapping corrections from upstream source. The Watchlist verifier now requires
external row-selection actions and selected-state queries on **all** platforms;
the earlier Windows diagnostic-selection fallback was removed. General Grid/Table
coordinate patterns and AT-SPI EditableText remain unimplemented. The real disabled
button assertion remains required on Linux. Updated Windows verification and hosted
runs are pending at this source checkpoint.

The patched Windows build now passes `watchlist-platform-4.json`: UIA
SelectionItem.Select reaches Dart and UIA IsSelected remains true through filter
clearing and sorting. The diagnostic-selection fallback is gone. Initial/full
view captures have 72 nodes, one-record views have 24; both contain the same
record/cell author IDs for BRK0025. Existing native construction/allocation tests
provide the separate viewport-scaling check. Before the dependency patch, Windows
57 native + 56 headless Dart + 6 live-window tests, 15 Settings steps, 9 control
steps, 100k JIT/AOT traces (zero dropped records) and 11 code reloads passed; raw
regression captures and source hash are in `windows-regression/`. Dependency-patch
checks are recorded separately as they complete.

The first patched hosted run confirms Linux disabled metadata and all 15 Settings
steps. Linux Watchlist then encountered the same transient stale-row read as AX:
AT-SPI returned its missing-object path while filtering (`linux-watchlist-1.json`).
The Linux client now reports that specific query-only failure with exit 75; the
Dart driver retries the whole read in a fresh process (clearing AT-SPI cache), at
most four times within one 20-second deadline. All restarts are retained; no
actions, permission errors or unrelated failures are retried.
