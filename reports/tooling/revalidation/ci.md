# CI and verification audit: PASS

Native replacement for the failed external Grok audit attempt, performed 2026-09-30. Audited HEAD: `a2600907a8013a5e890ce9c23c248f02f5f6887c`. Verified implementation: `d02a4ce7b6b317d0115ba7dac344e6b22e775eb4`. No material unmet migration requirement or falsely passing mandatory suite was found. This agent changed no tracked files and reran no expensive suite. During audit completion the parent added a historical release-index clarification and standalone Clippy receipts to retained evidence; implementation source remained unchanged.

## Revision and hosted receipts

`git diff --stat d02a4ce7b6b317d0115ba7dac344e6b22e775eb4 HEAD` contains only documentation and retained evidence changes; no workflow or implementation changed. `git status --short` was empty. Queried live GitHub metadata using `gh run view ID --repo AmeinEskinder/gpuidart --json headSha,conclusion,url,jobs`; all source workflow conclusions and relevant jobs are successful at `d02a4ce7...`:

| Workflow | Run |
| --- | --- |
| Windows SDK | 36656530654 |
| macOS SDK | 36656530660 |
| Linux SDK | 36656530640 |
| Accessibility | 36656535626 |
| Platform probe | 36656530729 |
| Unix lifecycle | 36656530692 |
| Release packages | 36656530668 |

Live `gh run list --repo AmeinEskinder/gpuidart --commit a2600907a8013a5e890ce9c23c248f02f5f6887c --json databaseId,workflowName,conclusion,status,headSha --limit 30` returned exactly four completed successful runs: Windows 36658300604, macOS 36658300588, Linux 36658300630 and Unix lifecycle 36658300539. Their individual run metadata and retained job/step records agree. None of the four has a failed or cancelled step.

The reduced final run set is explained by workflow triggers. The three SDK workflows and lifecycle run on every push. Accessibility and packages use path filters; platform probes also use path filters and manual dispatch. Final documentation changes do not match these source filters. The unchanged implementation already has successful source receipts for all seven workflows. The measurement workflows `performance.yml`, `snapshot-experiment.yml` and `encoding-experiment.yml` are explicitly manual and are not represented as newly executed mandatory migration gates.

## Full-check implementation and underlying results

The native CLI dispatches `check` to the actual Dart implementation (`bin/gpuidart.dart:47`), with failures returning nonzero. `tool/check.dart` immediately exits when either an inherited or captured subprocess fails (`:24`, `:43`); it is not a wrapper that merely prints commands. Reviewed every command:

| Requirement | Current command/location | Direct evidence |
| --- | --- | --- |
| Vendor provenance and allowed source languages | `dart run tool/accessibility/verify_vendor.dart`; `dart run tool/source_inventory.dart --report=build/source-inventory.json`, `tool/check.dart:47` | Source SDK logs show vendor verification and passing inventory on all targets |
| Rust formatting | `cargo fmt --all --check`, all three standalone helper manifests as applicable, and `rustfmt --edition 2024 --check test/fixtures/fault_host.rs`, `tool/check.dart:53` | Logged invocations complete successfully before subsequent gates |
| Helper compilation/tests | `cargo test --locked --manifest-path ...`, `tool/check.dart:54` | Windows log records native probe compilation with 0 unit tests (`validated-final/windows-sdk/run.log:582`), benchmark driver 1 passing test (`:625`), Windows helper 3 passing tests (`:673`); Unix logs record probe compilation and driver test |
| Native runtime and snapshot behavior | `cargo test --locked -p gpuidart`; snapshot feature experiment tests, `tool/check.dart:75` | Windows 111 passed, 2 ignored (`windows-sdk/run.log:816`); macOS/Linux each 115 passed, 1 ignored (`macos-sdk/run.log:458`, `linux-sdk/run.log:1537`); each platform has 3 passing snapshot tests |
| Native builds and CLI self-check | Native launcher build, normal native library build for full gate; rebuild CLI into `build/check` and run doctor, `tool/check.dart:62` | Hosted Windows log `:678` runs the separate CLI; avoids overwriting the running CLI; native compilation subsequently succeeds |
| Dart formatting and analysis | `dart format --output=none --set-exit-if-changed bin lib example test tool benchmarks`; `dart analyze --fatal-infos`, `tool/check.dart:96` | 177 formatted files, 0 changed; no analysis issues (`windows-sdk/run.log:851`, `:854`; corresponding Unix logs) |
| Benchmark analysis | `dart test benchmarks/analysis_test.dart`, `tool/check.dart:108` | 9 tests pass on every platform; Windows `:873`, macOS `:534`, Linux `:1583` |
| Actual FFI failure fixture and Dart contracts | Compile `fault_host.rs` as cdylib, run expanded Dart suite, `tool/check.dart:110` | Windows 141 passed (`windows-sdk/run.log:1055`); Unix headless 116 passed and 2 platform skips, plus 29 window tests on each OS |
| Documentation assertions | `tool/docs_check.dart`, `tool/check.dart:130` | Windows uses the just-measured 111/141 counts and passes (`windows-sdk/run.log:1057`); Unix checks applicable prose (`macos-sdk/run.log:684`, `linux-sdk/run.log:1733`) |

Paths above are relative to `.cache/migration-completion/` where prefixed with `validated-final`. Helper `cargo test` must not be described as more unit coverage than exists: the native probe has zero Rust unit tests. Its platform behavior is exercised through the external accessibility workflow on all three targets. The standalone helper manifests have their own `[workspace]`; `cargo fmt --all` and workspace Clippy alone would not cover them, but the full gate explicitly adds their formatting and test commands.

The actual earlier local native CLI full check is retained at `.cache/migration-completion/compiled-cli-full/result.json`, with exit 0 for `build/bin/gpuidart.exe check` at the recorded `8491da1...` source. Its stdout independently records 111 native, 3 snapshot, 9 analysis and 141 Dart passes, 177 files unchanged, no analysis issues and the documentation count check (`stdout.log:159`, `:173`, `:178`, `:181`, `:197`, `:379`, `:381`). The retained receipt is `reports/tooling/completion/local-full-check.json`. Current behavior is additionally proven by hosted source and final-SHA CLI checks.

## Platform/runtime/release coverage and failure propagation

Read all ten workflow files and their delegated command implementations. Windows runs the full native CLI check; Unix headless checks exclude only `live-window`, and their dependent window jobs explicitly run `dart test --tags live-window`, settings JIT/AOT, 100k-row JIT/AOT traces and real code reload. This is partitioned coverage, not a silent loss of graphical tests.

Accessibility builds the external Rust probe through Dart on each OS. `tool/native_probe/client.dart:11` always calls `cargo build --locked` before selecting the helper, so the restored binary cache cannot silently substitute stale source. Linux's numerous individually skipped workflow steps are all run within its successful Xvfb/D-Bus block (`.github/workflows/accessibility.yml:82`); Windows/macOS run the corresponding individual steps. Inspected all per-platform workflow step receipts and underlying Linux reports. Controls, disabled state, settings, watchlist, terminal JIT/AOT and reload have successful corresponding steps.

The platform feasibility probe explicitly requires main/worker/JIT/AOT/companion/reload outcomes on Linux. On macOS, direct non-main-thread launches must report the specific unsupported-thread result without timeout; a generic failure is not accepted, and companion JIT/AOT/reload must succeed (`tool/platform_probe/run.dart:316`). Windows native probing has its separate current local retained evidence; the hosted feasibility matrix intentionally contains macOS/Linux.

Release jobs compile the CLI natively on all three targets, execute packaging through it, verify extracted release/AOT archives, exercise compiled-CLI file-save reload and window-close shutdown, and retain both CLI and package artifacts (`.github/workflows/release-packages.yml:67`, `:79`, `:84`, `:97`, `:110`, `:146`). The Unix tar step preserves executable modes. Inspected successful per-step receipts and current package manifests/results. Windows failure cases explicitly reject tampering and absent self-test success, replace stale reports, hash ignored application entries and preserve Unicode (`reports/tooling/completion/windows-failure-cases.json:1`). Linux fresh-container and forced-scale checks execute within their successful matrix job. macOS ad-hoc evaluation signing and the hosted runtime-only limitation remain explicit.

No `continue-on-error`, `|| true` or unconditional successful-exit escape was found masking required verification. Shell pipelines use failure propagation where required, the Dart command wrappers throw on nonzero status, and retained result payloads support successful runs beyond the aggregate job status. PowerShell remains in short Windows workflow setup/command sequences, including explicit exit checks for packaging stages, as allowed by the task.

## Clippy coverage, without overstating it

Clippy is separate retained validation; `gpuidart check` and the hosted SDK workflows do not themselves invoke it. Examined receipts and stderr for:

- `.cache/migration-completion/clippy-final`: `cargo clippy --locked --workspace --all-targets --no-deps`, recorded at `8491da1f77e91cc6764aa5749000db0438f39387`, exit 0.
- `clippy-probe-final`: standalone native probe with `--all-targets --no-deps`, same source, exit 0.
- `clippy-macos-probe-final`: standalone native probe with `--target aarch64-apple-darwin --all-targets --no-deps`, same source, exit 0. This is a macOS-target compilation/lint receipt, not a claim that the whole framework was linted natively on macOS.
- `clippy-platform-final`: the changed `gpuidart-platform-probe` at `d02a4ce7...`, exit 0; receipt and actual warnings are copied to `reports/tooling/completion/platform-clippy.json` and `.log`.
- `.cache/migration-revalidation/clippy-windows-helper`: parent executed `dart run tool/env.dart cargo clippy --locked --manifest-path tool/windows/native/Cargo.toml --all-targets --no-deps` at `a2600907...` with implementation unchanged; independently inspected `result.json` and stderr, exit 0.
- `.cache/migration-revalidation/clippy-benchmark-driver`: parent executed the equivalent standalone command for `benchmarks/driver/Cargo.toml` at the same unchanged source; independently inspected `result.json` and stderr, exit 0. The parent is retaining these two explicit receipts in the completion evidence.

`git diff --name-status 8491da1 d02a4ce7...` shows that the sole Rust change after the earlier Clippy receipts is `tool/platform_probe/native/src/lib.rs`; the repeat Clippy run covers it. Native runtime, launcher, benchmarks, standalone native probe, Windows helper and dependency/toolchain manifests are unchanged, confirmed separately with a scoped `git diff --exit-code`.

The logs show 54 native-library warnings and 56 native-test warnings including duplicates, two Windows native-probe comparison suggestions, and three platform-probe let-unit-value warnings duplicated in its test build. The new standalone receipts each show one `chunks_exact_to_as_chunks` warning, duplicated for its test target: Windows helper `src/platform.rs:583`, benchmark driver `src/windows.rs:613`. They all exit 0; no claim of zero warnings or `-D warnings` compliance is supported. Together the receipts establish Windows workspace and standalone-helper Clippy, plus the explicit macOS-target native probe check. There is no supported claim of framework-wide all-platform or all-feature Clippy coverage; that broader lint campaign is not a required migration gate.

## Skips, legacy references and workflow lint

Declared skips correspond to source: the million-record timing probe (`native/src/protocol.rs:3318`), Windows startup timing probe (`native/src/startup_probe_tests.rs:52`) and two Windows-only preparation/verifier tests (`test/windows_preparation_test.dart:88`, `:157`). Unix lifecycle and companion tests are platform-scoped and run on Unix. The skipped timing measurements are not missing mandatory correctness tests. No newly disabled migration test was found.

`git ls-files '*.ps1' '*.psm1' '*.cs' '*.csx' '*.swift' '*.py' '*.pyw'` returned no files. Scoped searches of workflows, entry points, tooling, tests, manifests, active docs and benchmark drivers found no obsolete active invocation/dependency. Remaining hits are workflow shell names, shell-labelled documentation, explicit removed-entry migration tables, inventory extension recognition, tests proving legacy rejection, or explanatory comments. The manual measurement workflows now call Dart commands and Rust builds; none invokes the removed scripts.

No standalone actionlint receipt was found in the initially provided evidence paths, so I ran the cheap, read-only check directly against the final workflows: `actionlint -version` reported 1.7.12; `actionlint` returned exit 0 with no diagnostics. This closes that evidence gap without rerunning any compilation or runtime suite.

Scope limits: this is a source/command/receipt audit, supplemented only by live GitHub metadata and actionlint. No claim is added for notarization, clean Mac deployment, new Windows feature installation/Sandbox execution, physical presentation/IME, or rerunning every third-party benchmark fixture. Those are expressly separated from the completed migration in `docs/tooling-migration.md`. No corrective action is required for this partition.
