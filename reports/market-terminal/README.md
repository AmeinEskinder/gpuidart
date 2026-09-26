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
