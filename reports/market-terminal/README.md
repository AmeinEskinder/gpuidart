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
