# Dart and Rust tooling migration

The developer CLI and project tooling use Dart. Native runtime code and OS API
helpers use Rust. Small workflow commands may use the runner's shell. Third-party
comparison applications retain their own languages.

## Completion checks

- Maintained tooling has no PowerShell, C#, Swift, or Python implementation.
- Every removed entry point has a documented Dart or Rust replacement.
- Build, packaging, package verification, desktop probes, accessibility clients,
  and benchmark analysis retain their existing checks and failure behavior.
- Dart analysis, Rust compilation, and relevant automated tests pass.
- Platform behavior is marked verified only after running it on that platform.

## Work plan

- [x] Read the migration principles and inventory existing tooling.
- [x] Compare representative outputs against the implementations at `9f825a2`.
- [x] Move build, toolchain discovery, and packaging into Dart.
- [x] Move accessibility and platform probes into Rust.
- [x] Move Windows release orchestration into Dart and OS calls into Rust.
- [x] Move benchmark orchestration and analysis into Dart and input into Rust.
- [x] Update callers, CI, and current documentation; retain historical reports.
- [x] Review each independent change and run the integrated checks.
- [x] Audit evidence and document remaining platform verification limits.

## Entry points

Build the native Dart CLI with `dart run tool/build_cli.dart`. The output is
`build/bin/gpuidart.exe` on Windows and `build/bin/gpuidart` on Unix. It supports
`doctor`, `build`, `run`, `check`, `package`, `verify`, and `exec`. Development and
packaging still require an SDK checkout and the Dart/Rust/native build tools.
`GPUIDART_SDK` or `--sdk=PATH` selects the checkout.

All 38 maintained PowerShell, C#, Swift, and Python files were removed. These
replacements retain the existing command responsibilities:

| Removed entry points | Replacement |
| --- | --- |
| `tool/{build,build_test_fixtures,check,env,package,verify_package}.ps1` | Corresponding `.dart` files |
| `tool/{prepare_windows_release_checks,verify_mvp,verify_package_failures,verify_windows_prerequisites}.ps1` | Corresponding `.dart` files |
| `tool/windows/{capability_state,enable_release_checks,sandbox_release_check,verify}.ps1` | Corresponding `.dart` files; OS inspection in `tool/windows/native` |
| `tool/windows/watchlist_probe.ps1`, `tool/src/windows_powershell.dart` | `tool/src/windows_tool.dart` and `tool/windows/native` |
| `tool/accessibility/windows.ps1`, `windows_description.cs`, `windows_pointer.cs` | `tool/native_probe/src/windows.rs` |
| `tool/accessibility/linux.py`, `cache_events.py` | `tool/native_probe/src/linux.rs` and `linux/cache.rs` |
| `tool/accessibility/macos.swift`, `tool/platform_probe/metal.swift` | `tool/native_probe/src/macos.rs` |
| `benchmarks/{analyze,build,package,run,suite}.ps1` | Corresponding `.dart` files |
| `benchmarks/{analyze-input,build-trace,calibrate-wheel,install-presentmon,report-pair,resume-series,summarize-pair}.ps1` | Corresponding `.dart` files with underscores replacing hyphens |
| `benchmarks/{test-analysis,test-input-analysis}.ps1` | `benchmarks/analysis_test.dart` |
| `benchmarks/windows.cs` | `benchmarks/driver` Rust crate |
| `tool/performance/run_update_gate.ps1` | `tool/performance/run_update_gate.dart` |

Small shell commands remain in CI workflows and documentation. Third-party
comparison fixtures retain their implementation languages. Historical reports
retain the commands used at their recorded revisions.

## Verification

The local Windows full gate passed: 111 native tests, three snapshot experiment
tests, 140 Dart tests, nine benchmark analysis tests, helper-crate formatting and
tests, compiled CLI doctor, analyzer, and documentation checks. The full log is
`.cache/migration/integrated-check.log`.

Windows package extraction and standalone verification passed outside the
checkout with a restricted PATH, including AOT self-test, sibling runtime DLLs,
Common Controls v6, and PerMonitorV2 at 120 DPI. Failure checks rejected tampering
and missing self-test success, replaced stale success reports, hashed ignored
application entries, and preserved Unicode stdout/stderr. Watchlist interaction,
resize/scroll/update stability, code reload, startup failures, and child-process
cleanup passed through the replacement helpers.

Benchmark analysis matched the old scripts across 121 directories, 39 input
traces, six series summaries, and six Markdown reports. Two floating-point
round trips differed by about `5.68e-14`; all other values matched. Fresh Dart
fixture runs passed ten background clicks, ten foreground clicks, and 120
foreground wheel events, with zero missed input deadlines. Details are in
[benchmark_migration.json](../reports/tooling/benchmark_migration.json).

Windows accessibility passed all nine control steps and disabled-state checks
against the newly built runtime. One earlier query timed out while other
live-window tests were running; the serial rerun passed. Both attempts are
retained under `.cache/migration`. Run desktop accessibility checks serially.
The legacy/new tree comparison matched the 14 shared nodes; the native UIA
client also returned six real nonclient title-bar controls.

Linux helper build/link and GTK query, text, toggle, and absent-process checks
passed with Rust 1.98.1. Six GTK nodes matched the Python client exactly.
Typed cache signals on a private AT-SPI bus produced identical acceptance and
rejection results. These checks exercise the client; the GTK fixture emitted no
cache events to either client, so it cannot establish GPUI cache delivery.

## Remaining platform checks

- The macOS helper cross-checks, but runtime AX/Metal behavior and macOS linking
  need the macOS CI runner or a Mac.
- GPUI's Linux cache-event delivery still needs the hosted accessibility gate.
- Hosted workflows have been updated but have not run for this migration.
- Windows feature installation/restart and a new Sandbox launch were not run.
  Preparation and standalone package verification were exercised locally.
- Full Rust/Shell/Solid/Flutter benchmark fixture rebuilding and Unix analyzer
  execution were not repeated. The fresh input runs used the Dart fixture.

Independent GPT-6 Astra review found no remaining code blockers after fixes for
reserved package names, actual Dart SDK license discovery, source-only dirty
metadata, and separation of OS/setup queries from firmware identity checks.

The decision trail is in [tooling-migration.tsv](../reports/tooling-migration.tsv).
