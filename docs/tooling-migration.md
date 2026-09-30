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
- [x] Build native CLIs and release packages on Windows, macOS, and Linux.
- [x] Verify runtime, accessibility, reload, and packaging on all three targets.
- [x] Measure committed source and retain CI, artifact, and review evidence.

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

Source `8491da1` passed all seven hosted workflows. The
[completion report](../reports/tooling/completion.json) records source revisions,
test counts, artifact hashes, package provenance, and raw verification reports.

| Target | SDK tests | Runtime and release result |
| --- | --- | --- |
| Windows Server 2022 x64 | 111 native, 141 Dart, 3 snapshot, 9 benchmark analysis | PASS, native CLI, extracted release/AOT package, accessibility, reload and package failure cases |
| macOS 15 ARM64 | 115 native, 116 headless Dart, 29 window Dart, 3 snapshot, 9 benchmark analysis, 7 lifecycle | PASS, native CLI, Metal/AX runtime, companion JIT/AOT, extracted release package and reload |
| Ubuntu 24.04 x64 | 115 native, 116 headless Dart, 29 window Dart, 3 snapshot, 9 benchmark analysis, 7 lifecycle | PASS, native CLI, X11 runtime, AT-SPI cache events, extracted release package, clean runtime container and reload |

The native suites retain two ignored timing probes on Windows and one on each
Unix target. Each Unix Dart suite skips two Windows-only cases. Formatting,
Dart analysis, helper-crate checks, documentation checks, and actionlint passed.
Clippy completed successfully with existing warnings recorded in the report.
The actual Windows executable also passed `gpuidart check` locally. Its check
build goes under `build/check` so it cannot overwrite the running CLI.

Hosted evidence at this source revision:

- [Windows SDK](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102296),
  [macOS SDK](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102400), and
  [Linux SDK](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102270).
- [Three-platform accessibility](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102476).
  Linux received 50 cache additions and 47 removals with no invalid events.
- [Native platform probes](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102321) and
  [Unix process lifecycle](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102378).
- [Release packages and native CLI artifacts](https://github.com/AmeinEskinder/gpuidart/actions/runs/36652102472).
  All three package reports record `source_dirty: false` and source `8491da1`.
  Artifacts are retained for 30 days; their hashes are in the completion report.

The compiled CLI drove packaging, extraction verification, and file-watching
reload on all three targets. Windows package failure checks rejected tampering
and missing self-test success, replaced stale success reports, hashed ignored
application entries, and preserved Unicode output. Unix lifecycle tests proved
that interruption during both startup and watching stops the child application.
Accessibility checks covered controls, disabled state, settings, watchlist,
terminal JIT/AOT, and reload on each operating system.

## Measured source composition

`dart run tool/source_inventory.dart` reads committed Git blobs and rejects
maintained implementation outside Dart and Rust. It runs in the full check gate.
The [source inventory](../reports/tooling/source-composition.json) lists every
recognized source file, its Git object, scope, byte count, and line count.

| Maintained implementation at `8491da1` | Files | Bytes | Share |
| --- | ---: | ---: | ---: |
| Dart | 175 | 885,137 | 47.79% |
| Rust | 66 | 966,988 | 52.21% |
| PowerShell, C#, Swift, Python | 0 | 0 | 0% |

The baseline `9f825a2` contained 31 PowerShell, three C#, two Swift, and two
Python files. The completion report records all 38 removed paths. Percentages
use source bytes, without padding or removal to change the ratio.

Across all recognized repository source, including vendored dependencies,
comparison applications, and the C ABI header, the measured split is 84.35%
Rust, 15.15% Dart, and 0.51% C/C++/JavaScript/TypeScript after rounding. These
excluded scopes are explicit in the inventory. CI YAML, manifests, documentation,
and evidence are not implementation source. Historical reports retain old
commands as evidence of what ran at their recorded revisions.

## Earlier parity evidence

Benchmark analysis matched the old scripts across 121 directories, 39 input
traces, six series summaries, and six Markdown reports. Two floating-point
round trips differed by about `5.68e-14`; all other values matched. Fresh Dart
fixture runs passed ten background clicks, ten foreground clicks, and 120
foreground wheel events, with zero missed input deadlines. Details are in
[benchmark_migration.json](../reports/tooling/benchmark_migration.json).

The [earlier Windows migration record](../reports/tooling/verification.json)
retains the `f1cbb16` package and local verification. Earlier UIA comparisons
matched 14 shared nodes, with six additional real nonclient title-bar controls
from the Rust client. Linux GTK comparisons matched six nodes and private-bus
cache signal acceptance. The final hosted checks above exercise GPUI itself.

## Verification scope

The three declared targets are verified for development and evaluation releases.
The macOS package uses ad-hoc signing and is not notarized. Its runtime-only
check disables developer-tool discovery on a hosted development machine. Linux
also passed in a fresh container without Dart or Rust SDKs; `ldd` dependency
inspection remained enabled. Hosted graphics do not establish physical display,
mixed-monitor, or human IME behavior. Clean Mac deployment and distribution
signing remain separate product-release acceptance work.

Windows feature installation/restart and a new Sandbox launch were not repeated.
Full third-party benchmark fixture rebuilding was not repeated; analysis parity,
fresh Dart fixture input, and the automated analysis suites were verified.
Existing backend limits include Linux EditableText and Windows UIA Grid/Table
coordinate patterns. These are recorded capabilities, not legacy implementations.

Independent review by GPT-6 Astra and Claude Fable 5.1 identified and closed
native CLI self-check, Windows path/environment, process cleanup, and stale
accessibility-read bugs. Grok 4.6 reviewed packaging and command responsibilities.

The decision trail is in [tooling-migration.tsv](../reports/tooling-migration.tsv).
