# Accessibility milestone: results and evidence

The semantics model and native adapters are implemented. The external platform
track passes on Windows, Linux X11 and macOS at `8b612de` in
[run 36277069695](https://github.com/AmeinEskinder/gpuidart/actions/runs/36277069695).
All five SDK/lifecycle/accessibility workflows pass at that source commit
([recorded CI jobs](hosted/ci.json)). The milestone is complete within its
programmatic scope; it does not establish human screen-reader usability.

## Accepted platform evidence

Raw responses, per-file hashes and the exact source commit are in
[hosted/manifest.json](hosted/manifest.json). Every platform runs the same settings
application and the real 100,000-record Watchlist, using an external OS client.

| Check | Windows 2022 / UIA | Ubuntu 24.04 X11 / AT-SPI | macOS 15 ARM64 / AX |
| --- | --- | --- | --- |
| Control roles, names, values and actions | 9 steps passed | 9 steps passed | 9 steps passed |
| Disabled states and inert/rejected actions | Passed | Passed | Passed |
| Settings semantics alongside keyboard/retention verifier | 15 steps passed | 15 steps passed | 15 steps passed |
| Watchlist filter, selection, price edit and sort | 7 steps passed | 7 steps passed | 7 steps passed |
| Initial platform nodes over 100k source records | 72 | 73 | 80 |
| External row selection and selected-state query | SelectionItem | AT-SPI Action/state | AXPress/AXSelected |

Inputs, buttons, checkboxes, sliders, selects, modal content, headings and table
rows/cells use the real GPUI/AccessKit tree. Native state supplies values, checked,
disabled, focus and selection. Explicit annotations supply bounded names and
compatible roles; they cannot override behavior. Snapshot acknowledgement is not
an OS accessibility publication fence; the verifiers await platform state.

Watchlist verifies the same BRK0025 row author ID after filter clearing and sorting,
reads its formatted `101.82` price, and observes selection removal when filtered
out. It sends only one dataset update (the price edit). Platform tree counts are
viewport observations; existing native construction/allocation tests provide the
separate scaling check. Offscreen retrieval is not established.

Linux Watchlist needed three whole-query restarts, each retained in its report:
two disposed-object errors with a successful fresh application-root request, and
one missing-object error. Windows/macOS needed none in these accepted Watchlist
captures. No partial tree or repeated action was accepted. The independent Linux
cache observer received 50 additions and 47 removals with valid argument types and
zero invalid signals. Client deprecation warnings remain in raw stderr.

## Regression and maintenance scope

[Local Windows results](windows-final/manifest.json) record 57 native library tests,
56 headless Dart tests, 6 live-window tests, 100k JIT/AOT smokes (30 cell edits and
30 snapshot updates each), and 11 successful code reloads with retained state.
The JIT/AOT traces contain 1,040 / 1,017 records and the reload trace 1,078; all
report zero drops and complete capture. These use a debug native DLL. AOT describes
Dart compilation; these are correctness captures, not performance measurements.
The manifest preserves the capture's source identity separately from later
Unix-only changes. Original PowerShell logs retain UTF-16 encoding; hashes describe
exact bytes and are protected from checkout newline conversion.

Hosted [Linux SDK checks](https://github.com/AmeinEskinder/gpuidart/actions/runs/36277069642)
and [macOS SDK checks](https://github.com/AmeinEskinder/gpuidart/actions/runs/36277069665)
pass headless suites, live-window lifecycle, 100k JIT/AOT publication smokes, Settings
JIT/AOT and reload. Their reload fixture has 1,000 rows; the local Windows reload
fixture above has 100,000. Both hosted platforms retain complete traces with zero
drops in [the manifest](hosted/manifest.json).
[Windows SDK checks](https://github.com/AmeinEskinder/gpuidart/actions/runs/36277069617)
and [Unix process lifecycle](https://github.com/AmeinEskinder/gpuidart/actions/runs/36277069614)
also pass. These checks supplement the external accessibility workflow; their
internal diagnostics do not substitute for UIA, AT-SPI or AX evidence.

Four version-preserving AccessKit overrides fix disabled-button metadata, row
selection mapping and cache-signal encoding. One GPUI method associates the input
semantic node with its actual editing focus without introducing a tab stop.
[Provenance, licenses and small patch diffs](../../native/vendor/README.md) are
separate from copied upstream source. The 160-file digest gate runs on every SDK
check. Updating the toolkit must pass these same external regression checks;
these fixes are maintained locally and are not attributed to unmodified upstream.

## Limits carried forward

- Linux has no AT-SPI EditableText at this pin. Fixture text edits use declared
  GPUI diagnostic keys; the subsequent value reads are real external AT-SPI Text
  queries. Windows/macOS text writes use their external platform APIs.
- Text selection/caret actions and glyph geometry are not added. Windows Grid/Table
  coordinate patterns and offscreen virtual-table navigation remain unsupported.
- macOS modal content, dialog subrole and decisions are checked; a missing AXModal
  property is not inferred from the internal modal flag.
- No screen-reader speech/navigation, visual layout/contrast, Wayland, controlled
  hardware IME, Mac physical display, signing or presentation-latency claim.
  Live-region announcements remain unbound and unverified.
- Parked hardware/signing and historical reload-disposition gates remain open.
  This milestone does not declare the overall stable-release goal complete.

The chronological checkpoints below retain earlier incomplete states and failed
attempts. The accepted results above describe the current implementation.

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

## Historical native-adapter checkpoint

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

Patched run [36274755091](https://github.com/AmeinEskinder/gpuidart/actions/runs/36274755091)
passes all platform steps on Windows and macOS, including real row selection and
selected-state queries through sort/filter. Linux's disabled assertion and Settings
track pass; only its stale Watchlist query failed. Local patched Windows also
passes all 57 native tests, disabled checks and 15 Settings steps. The Dart analyzer
reported a missing-braces style issue in the new provenance verifier; it was fixed
before the final fatal-info gate. The 40-file provenance check passes locally.

## Focus audit and query diagnostics

The final audit found native input focus was true while the input's accessibility
node was unfocused in the isolated X11 capture. Kit's outer input frame tracks a
proxy focus handle; the editing entity has the real handle. Retargeting the frame
created duplicate tab stops and failed Settings appearance navigation after
Shift+Tab (`windows-input-focus-rejected.json`), despite headless tests passing.
That change was reverted. A narrow [GPUI 0.3.6 hook](../../native/vendor/focus.patch)
now associates the semantic node with editing focus during prepaint, preserving
the original keyboard tree/tab stops. External Focus must focus the real input;
the Linux Settings track additionally checks native/platform focus equality.
Platform role assertions are explicit for inputs, controls, table rows and cells.

Linux's next failed query used the second D-Bus spelling for a stale object,
`Unknown object '/org/a11y/atspi/accessible/...'` (`linux-stale-object-2.json`). The
same bounded read-restart policy now recognizes both observed missing-object
messages. Successful clients now retain stderr too: AT-SPI cache-signature
warnings are evidence, not proof of working cache notifications. The acceptance
track checks external queries/actions, not assistive-technology cache-event
consumption or a human screen reader. Those remain explicit limits.

The focus hook passes locally: `windows-focus-controls.json` records an external
UIA Focus request followed by native input `focused: true`; `windows-settings-focus-fixed.json`
passes all 15 keyboard/retention steps that the rejected retargeting broke. Input
and other control roles are now asserted explicitly in platform responses. The
GPUI source import is 99 files / about 2.96 MB, with one 16-line Window method
addition; its complete source delta is separate from copied upstream code. This
is a maintained local framework extension, not an upstream GPUI API claim.

## Linux cache-signal premise audit

The initial premise was that the Linux read failures were solely concurrent
traversal invalidation. Run 36275977185 passes controls, disabled controls and all
15 Settings steps, including native/platform focus agreement, but Watchlist
receives a null child after reading its parent count (`linux-stale-child-3.json`).
The repeated captures also retain malformed cache-signal warnings. Source review
found a provider defect: accesskit_unix passes the fields of each cache record as
separate D-Bus arguments. The
[AT-SPI Cache specification](https://raw.githubusercontent.com/GNOME/at-spi2-core/main/xml/Cache.xml)
requires a single struct argument for each AddAccessible and RemoveAccessible.

The two-line Unix adapter correction wraps each record in a single-element tuple.
An external bus observer now validates argument count and type for both signal
kinds, scoped to the native process PID, during the control verifier. Its result
is recorded separately from platform queries. This is a test of wire delivery,
not a screen-reader claim. Hosted validation is pending at this checkpoint.
Disappearing children still invalidate a multi-call read; that explicit case now
uses the existing bounded, query-only whole-tree restart policy. Partial trees
are never accepted and actions are never replayed. The new monitor will determine
whether the provider correction fixes the malformed signals; retries cannot
mask a failed signal assertion.

Run [36276761058](https://github.com/AmeinEskinder/gpuidart/actions/runs/36276761058)
confirms the cache correction: the owned Linux process emitted 50 additions and
47 removals with no invalid signatures (`linux-cache-signals-1.json`). Controls,
disabled controls and Settings pass. Watchlist fails with AT-SPI APPLICATION_GONE
while reading a filtered-out object (`linux-disposed-object-4.json`).
[libatspi's removal handler](https://raw.githubusercontent.com/GNOME/at-spi2-core/main/atspi/atspi-misc.c)
disposes a removed accessible; its
[object disposal](https://raw.githubusercontent.com/GNOME/at-spi2-core/main/atspi/atspi-object.c)
clears that object's application pointer. The error therefore does not by itself
establish a process exit. The verifier now permits its existing bounded query
restart only if the same owned application root answers a fresh AccessibleId
property round-trip. A dead/unresponsive root still fails. It does not use cached
PID/name as proof of liveness. Final query failures also retain an application
inspect attempt to separate provider reads from application exits. No action
retry or partial-tree acceptance was added.

## Windows query timeout retained (`2489008`)

The Windows probe failed once at `2489008`, the commit that makes the host
repaint as soon as an update from the application is applied, and passed at
`4f776ba` before it. The report from the run's artifact is retained as
`windows-spike-2.json` (run
[36633135956](https://github.com/AmeinEskinder/gpuidart/actions/runs/36633135956);
`gh run download` times out against the artifact store from this machine, the
API's zip endpoint through curl works). The very first platform query timed out
after 20 seconds, at `probe.dart:26` and before any Invoke, so the two
suspected mechanisms, the repaint diagnostic's frame count and a paint between
the Invoke and the section change, are not what happened: neither had run yet.
A passing probe on that runner takes 6.5 seconds end to end, so the query hung
rather than ran slowly.

Not reproduced. The probe passed 29 of 29 local runs with the repaint on, and
the Windows job passed six CI runs in a row on the same native code
(`70db97e` pushed, four dispatched samples, `9f825a2` pushed). The same step
also failed at `6731fca` on 2026-09-28, before the repaint existed, with a
thread-local panic at shutdown, so the step has a history that one failure
against one pass does not settle. The cause is open.

So that a recurrence explains itself, `9f825a2` makes the Windows client write
its stage on stderr (window found, elements counted, descriptions read, nodes
built) and the query deadline error carries those stages; the probe records
whether the host still answered an inspect after a failure
(`host_after_failure`), which separates a blocked host thread from a client
that hung on its own. Stage lines are kept out of the retained responses.
