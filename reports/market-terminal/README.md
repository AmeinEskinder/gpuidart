# Market terminal milestone ? implementation evidence

Work order: [design](../../docs/market-terminal.md). This report is in progress;
feature checks below do not establish the complete milestone acceptance bar.

## Theme as snapshot data

- Light/dark descriptors and at most 16 opaque `#RRGGBB` overrides use the
  existing token vocabulary. Native and Dart boundaries reject unknown tokens,
  alpha, references and extra fields. Omission resets the built-in light theme.
- Each changed descriptor starts from Kit's immutable registered default config.
  Kit resolves component fallbacks and synchronizes Component tokens and Base.
  Overridden primary/secondary/status colors recompute their hover/active colors.
  Other explicit component colors in the built-in config remain that palette's
  colors: this API exposes the SDK tokens, not every field in Kit's theme schema.
- The `openView` theme callback is evaluated on rebuild. It retains app-owned
  theme choices when the dev launcher rebuilds after reload. Actual terminal
  code-reload verification remains pending until the app is assembled.

Windows checks on 2026-09-27: `cargo test --locked -p gpuidart --lib --
--test-threads=1` passed 59 tests; `cargo build --locked -p gpuidart` passed;
`dart analyze --fatal-infos` clean; `dart test test/theme_test.dart
 test/theme_host_test.dart --reporter expanded` passed 3 tests, including a real
window. Native theme test checks input value/selection/focus, input/table entity
identity, scroll retention, invalid-theme atomic rejection, removed overrides,
resolved primary button tokens and the Base projection. These are debug checks,
not timing or visual-quality measurements. Contrast acceptance is still pending.

Retained implementation observations:

- First Cargo invocation used PowerShell's `Stop` error preference with stderr
  redirection, so a normal `Compiling` line interrupted the command. Retried with
  `Continue` and explicit exit-code handling; no native failure was inferred.
- Source inspection caught that mutating only `ThemeColor.primary` does not
  recompute `button_primary`. The implementation now applies a validated Kit
  configuration, with a regression assertion on the actual button token.

## Remaining acceptance

Navigation chrome, charts, terminal assembly, platform accessibility probes,
real reload, 100k regressions, final CI and documentation are pending. Human
visual/screen-reader behavior, presentation latency, physical Mac observations,
signing and the historical Windows reload disposition remain outside this task.

## Tabs

`UiTabs` binds Kit Base Tab to a host-owned focus group: stable option IDs,
1..32 choices, manual activation, arrows/Home/End, disabled-choice skipping,
one tab stop, and current-snapshot validation before events. Focus-handle
identity rejects callbacks from a removed/remounted group without discarding
valid clicks just because a snapshot revision advanced. Semantics derive tab
roles, selected/disabled states and set positions from real controls.

Windows checks: 64 native tests with `snapshot-experiment` enabled passed;
Dart analyzer clean; 2 wire tests and 1 live-window keyboard/event/rebuild test
passed. Native tests cover names/roles, focus versus selection, reordering,
pointer/keyboard activation, disabled groups and stale callbacks. External OS
queries are deferred to terminal fixture verification, not inferred here.

Retained attempts: initial compile needed materialization's existing view
context forwarded to listeners and the App argument to `blur`. A test glob
import recursively shadowed the Rust test attribute; explicit imports fixed it.
Kit's observed tab snapshot cannot report a focus handle supplied before its
internal observation wrapper; attempting to add an outer wrapper is unsupported
for that render-once control. Focus assertions now query the actual retained
GPUI focus handles, with the live keyboard round trip checking the same behavior.
The failed focus-inspection attempt was a verifier limitation, not an observed
failure to move focus. The separate role/selected/name assertions remain.

## Application menus

Snapshot menus map to real GPUI Menu/MenuItem values, with Kit's in-window bar
on Windows/Linux and the native app menu on macOS. Global action bindings supply
the shortcuts; comma is now an allowed modified printable key. Scoped actions
keep precedence. Disabled menu commands suppress their global shortcut when all
entries referencing that command are disabled. Removal of a menu does not remove
a separately declared application action. Invoke carries menu/entry/action
identity and validates all three against the current snapshot.

Windows native menu tests passed: bounded wire/round trip; real popup role and
item; Escape focus restoration; keyboard activation; unchanged-open-menu
publication; disabled/stale invocation; scoped shortcuts; unchanged keymap counts
after repeated publications. Dart wire tests passed and analyzer is clean.
The accessibility workflow now runs theme/tab/menu live FFI tests on all three
platforms. External native-menu queries remain a terminal-fixture gate.

Local DLL build attempts are retained as failures, with the live menu Dart test
pending a new DLL or hosted run. First `rustc` exhausted allocation capacity.
Disabling incremental compilation globally also exhausted memory while compiling
Kit (it invalidated dependency caches). A package-only override then compiled
the host but MSVC linking failed with LNK1102, out of memory. Windows reported
about 2.4?3.1 GiB free commit capacity between attempts; this is build-environment
evidence, not an application memory measurement or proof of a compiler defect.
Logs: `build/terminal-menu-build-no-incremental.log` and
`build/terminal-menu-build-package-only.log` (local build files, not release
artifacts). No system-memory settings or unrelated processes were changed.

The premise that changing compiler caching alone would unblock the full build
was not supported. Hosted verification is the next independent check while local
capacity is constrained. The headless menu tests themselves passed both before
and after the failed DLL build attempts. A Dart lint check also caught three
missing statement braces, corrected before this commit.

### Hosted menu follow-up

Commit `7b40185` passed all five workflows, including the new live FFI tests on
Windows/macOS/Linux: [accessibility + live navigation](https://github.com/AmeinEskinder/gpuidart/actions/runs/36280450498),
[Windows](https://github.com/AmeinEskinder/gpuidart/actions/runs/36280450416),
[Linux](https://github.com/AmeinEskinder/gpuidart/actions/runs/36280450436),
[macOS](https://github.com/AmeinEskinder/gpuidart/actions/runs/36280450423),
[Unix lifecycle](https://github.com/AmeinEskinder/gpuidart/actions/runs/36280450469).
The hosted pass closes the menu live-bridge check; local linker failures remain
in the record. The complete local native suite also passed 63 tests at that tip.

## Row context menus

Kit's table hook receives a row index and its built-in popup opens in a deferred
callback. It has no public keyboard-open method. A narrow host-owned session
therefore captures record identity from the rendered row and uses Kit PopupMenu
for pointer/keyboard activation and dismissal. A row capture handler suppresses
the table's built-in empty popup (the test asserts exactly one Menu). Shift+F10
uses the selected record; its popup anchors at the window center and snaps inside
the window. Pointer popups anchor at the click.

A session retains the table entity, dataset identity, replacement generation,
source index and record ID. Edits preserve the generation; replacement advances
it. Sort/filter changes cannot retarget the captured record. A filtered-out
record remains a valid target while it exists in the same dataset generation.
Replacement/removal or a changed context-menu descriptor cancels the popup;
callbacks validate independently before emitting `row_action`, including before
the next draw. Events report the current dataset revision and stable record ID.
No full-dataset search or Dart callback is required to render menu entries.

Windows: 65 native tests passed, including real right-click/Shift+F10, native menu
roles, focus restoration, sorting, incremental edits, disabled commands, stale
callbacks before repaint, replacement cancellation and initial identity rejection.
Dart wire test passed; direct SDK `dart analyze --fatal-infos` clean. The new live
row-command test is queued in hosted verification; no local live pass is claimed.

Retained failures/findings:

- The first Escape assertion ran before GPUI flushed the DismissEvent subscriber.
  It failed, then passed when checked in the next app update. Native key dispatch
  itself was unchanged; the verifier now observes the asynchronous contract.
- While checking dataset replacement, source inspection showed that an existing
  sort/filter could reference a column removed by replacement. Replacement now
  validates consumer columns and record-ID requirements before changing data.
  The regression asserts rejection leaves revision and column count unchanged.
- One local analyzer launch failed with a PowerShell out-of-memory error in
  Flutter's Dart wrapper. Running the installed Dart SDK executable directly
  completed analysis; the failed wrapper launch is not counted as a pass.

### Hosted row-menu follow-up

All five workflows passed at `230fe60`, including the live row-command bridge
test on Windows/macOS/Linux.

## Tooltips

Buttons accept optional help of 1..1024 UTF-8 bytes, separately from their name.
Kit owns hover timing and the popup; the same text sets the button's AccessKit
description through the existing root-properties adapter. No extra focus stop or
wrapper accessibility node is introduced.

Windows headless tests passed for byte bounds, hover dispatch and unchanged button
name; the Dart wire test passed. Popup appearance/dismissal and external HelpText,
description or AXHelp queries remain terminal-fixture checks.

Retained attempts: the initial implementation tried StatefulInteractiveElement
methods directly on Kit Component Button, which only exposes InteractiveElement.
The existing root-properties adapter is the supported host boundary. An initial
headless test then timed out looking up `tooltip-popup`: Base Tooltip does not
register with Kit's opt-in test observer. That result does not establish whether
the tooltip painted. External accessibility queries will check the actual popup.

## Radio groups

UiRadioGroup shares the validated stable choices and retained focus implementation
with tabs. Kit Base Radio supplies native checked/selected semantics and pointer
activation. Arrows/Home/End focus and request a selection; Space on the accepted
choice is inert. One tab stop, disabled choices, reordered identity and stale
callbacks have native regression coverage. Changing between tabs and radios at
the same node ID creates fresh control generations. Both use theme tokens and
native focus styling.

Windows: all 68 native tests passed. Five focused Dart tests passed for radio,
tabs and tooltip wire behavior. The live radio event/acknowledgement test is added
to all three hosted accessibility jobs. It checks that arrow activation returns
to Dart and a publication accepts the selection while retaining focus.

Retained verifier failures: a mechanical test adaptation produced an invalid
Dart variable name, fixed before running the successful tests. The analyzer also
caught the tooltip codec's null-element style rule; the codec now uses Dart's
null-aware map element. These were test/lint failures, not native runtime failures.

### Hosted radio follow-up

The radio live bridge and accessibility workflow passed on all three platforms
at `58db8c5`; the remaining SDK jobs are tracked before final acceptance.

## Dataset charts

Line and bar use Kit's native chart components, with a cached projection from the
same datasets and views as tables. A chart consumes at most 512 trailing candidate
rows. Non-numeric/non-finite values or magnitudes over 1e12 are omitted and counted,
without backfilling or zero substitution. A line connects valid points across
omissions; that policy is explicit in the design. Labels are capped at 128 Unicode
scalars. Internal axis keys retain source identity separately from displayed
labels, so duplicate labels do not collapse multiple records into one position.

Native Group semantics describe the chart and bounded point Labels use record
IDs. Pinned AccessKit has no Chart role. The same cached points feed Kit, summary,
diagnostics and point alternatives. Relevant column edits recompute; unrelated
columns only advance the observed dataset revision. Unchanged publications reuse
the point allocation. Dataset replacement validates chart columns/view references;
release rejects while a chart still references the dataset.

Windows native tests passed for both actual Kit render paths over a 100k source,
12-point tails, unchanged allocation identity, relevant/unrelated edits, invalid
values, negative values, filter changes, empty views, and atomic replacement/release
rejection. Dart bounds/wire tests and analyzer passed. A live chart bridge test is
added to the three hosted platform jobs. No chart visual-quality claim is made.

Retained implementation failures: the first nested JSON fixture needed parentheses
around its mapped array expression. Dart's sealed UiNode also required the chart
declaration to be a part of its library rather than an independent subclass file;
analysis caught this before live execution.

### Hosted chart follow-up

All five workflows passed at `dfa65ae`, including line/bar live dataset edits on
Windows/macOS/Linux. The SDK jobs also kept existing 100k and settings fixtures green.

## Terminal assembly: verification in progress

The terminal now assembles all three tracks. The new verifier runs 100k-record
interaction and external platform semantics, an AOT interaction pass, and actual
Dart-code reload on all three hosted platforms. Each report starts failed and only
passes after its declared assertions. The external clients gain accessible help
reads and OS pointer movement to the owned element's queried bounds for tooltip
appearance/dismissal. macOS explicitly queries AXMenuBar.

Local analysis was attempted after assembly but the Dart VM could not start a
worker thread. Windows then reported under 1 GiB free commit capacity; no app test
ran in that attempt. Hosted checks and a retained matching Windows DLL provide an
independent verification path. Terminal acceptance is pending, not inferred from
the prior control-family passes.
