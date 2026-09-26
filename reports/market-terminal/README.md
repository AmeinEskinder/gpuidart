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
