# macOS migration audit: PASS

Audited final commit `a2600907a8013a5e890ce9c23c248f02f5f6887c` and implementation/evidence commit `d02a4ce7b6b317d0115ba7dac344e6b22e775eb4`. No remaining macOS migration blocker was found. Repository implementation was read-only; no suites were rerun.

## Revision and hosted-run verification

- `git rev-parse HEAD` returned the final commit and `git status --short` was empty. `git diff --name-only d02a4ce7b6b317d0115ba7dac344e6b22e775eb4 a2600907a8013a5e890ce9c23c248f02f5f6887c` contains only docs/reports. I independently compared Git tree object IDs for all 422 records in `reports/tooling/source-composition.json`: zero source-blob differences.
- Live `gh run view` metadata confirms final macOS SDK run **36658300588** at `a260090...`: both `headless` and `window` succeeded. Final Unix lifecycle run **36658300539** succeeded at the same commit, including `processes (macos-15)`.
- Live metadata confirms package **36656530668**, accessibility **36656535626**, and platform **36656530729** runs succeeded at exactly `d02a4ce...`, including each macOS job. Source SDK run **36656530660** is retained with its complete logs/metadata.
- I read final SDK logs using `gh run view 36658300588 --repo AmeinEskinder/gpuidart --log`. They show 115 native tests passing (one expressly ignored million-record timing probe), 3 snapshot tests, 9 benchmark-analysis tests, 116 headless Dart tests (two Windows-only skips), 29 real-window tests, zero format changes, and `No issues found!`. Settings JIT/AOT each passed 15 steps. Source logs independently give the same results at `.cache/migration-completion/validated-final/macos-sdk/run.log:458`, `:506`, `:512`, `:515`, `:534`, `:682`, and `:1059`. Source lifecycle logs record 7 macOS tests passing at `.cache/migration-completion/validated-final/lifecycle/run.log:418`. Windows-only skip guards are `test/windows_preparation_test.dart:88` and `:157`.

## Main thread, Metal, positive paths, and negative probes

- The maintained macOS AX/Metal implementation is Rust: `tool/native_probe/src/macos.rs:53` declares AX functions, `:292` performs AX actions, and `:379` implements Metal enumeration. Searches of active accessibility/probe code and macOS/release workflows found no remaining Swift/Python/C#/PowerShell implementation invocation in this scope.
- Raw `metal.stdout.log:1` reports an Apple Paravirtual Metal device and explicitly limits the claim to device enumeration. This is hosted Metal capability, not a physical GPU/presentation assertion.
- Exactly three probes intentionally reject off-main-thread launch: `rust-worker`, `dart-jit`, and `dart-aot` exit 1, report `rejected_non_main_thread`, and have `main_thread:0`. Direct Dart results carry native status -10. They do not time out. Raw evidence is under `.cache/migration-completion/validated-final/platform/platform-probe-macOS-ARM64/`, in the corresponding `*.stdout.log` files. Source rejects this path at `tool/platform_probe/native/src/lib.rs:189`; `tool/platform_probe/run.dart:171` recognizes the exact rejection and `:321` requires successful native-main/companion paths separately.
- `rust-main.stdout.log` proves main-thread application/render callbacks, a resized 720x420 render, one click, matching input, and 13 renders before quit. Its synthetic GPUI input explicitly bypasses OS injection/IME.
- Companion JIT and AOT both return zero after resized rendering, native callbacks, applied labels, and independent Dart heartbeat progress: 22 and 17 ticks respectively. AOT checkpoints are retained at `reports/tooling/completion/macos-companion-aot.log:1`; `:9` records resized rendering and `:12` records successful completion. The fix waits for both `resized.future` and `heartbeatReady.future` before closing (`tool/platform_probe/companion.dart:74`), and final acceptance requires resize evidence, heartbeat, and a macOS main-thread callback (`:115`). Thus the short AOT execution cannot pass by closing before the resize or first heartbeat.
- `reload.json` proves label replacement with the same Dart/native process IDs and input entity/value; invalid source is rejected and recovery succeeds. `reports/tooling/completion/cli-reload-macOS-ARM64.json:1` independently confirms file-save reload via the compiled CLI and native-window close stopping the launcher.
- Production code follows the same architecture: `launcher/src/main.rs:16` loads the sibling SDK and calls `gd_ui_process_main` directly; macOS `native/src/lib.rs:358` runs the UI without creating a worker thread. Both package runtime reports independently confirm the actual UI process runs on the main thread.

## Accessibility, JIT/AOT, and reload evidence

I inspected the underlying JSON artifacts under `.cache/migration-completion/validated-final/accessibility/accessibility-macOS-ARM64/`, not only the completion summary. All eight reports pass:

- `controls.json`: 9 external AX checks including checkbox, text, range writes, modal cancellation and confirmation reaching application state.
- `disabled.json`: disabled controls expose no actions and retain state after attempted actions; reenabled controls expose their supported actions.
- `watchlist.json`: 7 external AX checks over 100k records, bounded trees (80 nodes, 32 when filtered), selection of BRK0025, incremental cell update, selection identity across sorting, and filtered-out selection removal. `unavailable` is empty. Transient invalid AX references trigger recorded query restarts, followed by successful complete queries.
- `settings.json`: 15 interaction/state steps. `terminal-jit.json` and `terminal-aot.json`: each 15 steps covering 100k datasets, native controls, tabs/menus, theme and draft persistence.
- `terminal-reload.json`: title changes to `Market terminal reloaded` while native PID 8979, input entity 4294967331, text `ada`, selection 1..2, focus and application state are preserved.
- `platform-spike.json`: actual AXUIElement roles/actions for settings.

These are external AX and real-window claims. They do not claim human screen-reader, physical display, or IME acceptance.

## Package, native CLI, and provenance

I opened both downloaded tarballs with Python `tarfile` in memory, computed SHA-256, inspected ARM64 Mach-O headers, and checked every payload size/hash against the archive manifest. No files were extracted or modified.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Watchlist-macos-arm64.tar.gz` | 13,991,272 | `2b75436a1daa55f03b1ab4ee61974de10770574c24638900aae0e512e2721635` |
| `gpuidart-cli.tar.gz` | 3,087,126 | `bea35bb69ec8f713296d65a2d08e78107ed4fe5478651c911e289ef712315386` |

Both match `reports/tooling/completion.json:674` and `:695`. All 17 package payload file hashes/sizes match. The archive manifest records clean source `d02a4ce...`; all **412 source file SHA-256 values** independently match bytes read from that revision with `git cat-file --batch`. The CLI tar preserves mode 0755; its executable is 7,598,960 bytes with SHA-256 `a0e965467b9b69a07aca1ee4ebc180c461d0eae4a20fa32c4719043cdd50c30f`. CLI, Watchlist, verifier, launcher, and SDK dylib have ARM64 Mach-O headers. `tool/build_cli.dart:20` compiles `bin/gpuidart.dart` to a native executable.

The workflow builds and runs the native CLI (`.github/workflows/release-packages.yml`), then uses it to package and verify the extracted release/AOT app. Build log lines 50-57 show AOT compilation, ad-hoc signing and strict signature verification; line 72 records the exact archive hash. Doctor and compiled-CLI reload reports pass.

Normal and runtime-only package reports show AOT application success, exit 0, and native window geometry 960x653 at scale 1. Each uses an isolated working directory/home and system PATH. I independently examined all loaded images: application/UI list 489/948 images, all inside the extracted package or system directories. Both load the packaged `libgpuidart.dylib`. Normal application/UI PIDs are 7987/7988; runtime-only PIDs are 8170/8171. UI `main_thread` is true in both reports (`reports/tooling/completion/package-macOS-ARM64.json:3433`).

Runtime-only semantics are honest and enforced: `tool/unix/verify.dart:103` uses retained build-time dependency inspection instead of invoking `otool`; payload hashes (`:82`), signature validation (`:133`), actual loaded-image checks (`:195`), distinct main-thread UI process (`:228`), and window checks remain required. The workflow first proves `xcrun --find otool` fails with invalid `DEVELOPER_DIR`; the raw `unavailable-otool.log:1` records that failure. Both reports declare `development_machine`, not clean Mac deployment. Ad-hoc signing and no notarization are explicit in manifest/report/documentation (`docs/tooling-migration.md:154`).

## Commands and limits

Recorded commands examined include `dart run tool/build_cli.dart`, `build/bin/gpuidart check --headless`, `dart test --tags live-window`, settings JIT/AOT verifiers, JIT/AOT publication trace capture, Watchlist reload verifier, `dart run tool/platform_probe/run.dart`, `build/bin/gpuidart package --name=Watchlist`, ordinary and `--runtime-only` archive verification, `dart run tool/run_host_baselines.dart`, and `tool/verify_dev_launcher.dart` with the compiled CLI. Mac-native probe Clippy evidence uses `cargo clippy --locked --manifest-path tool/native_probe/Cargo.toml --target aarch64-apple-darwin --all-targets --no-deps`; its raw result/stderr show exit 0. That crate has no changes between the earlier lint revision `8491da1...` and `d02a4ce...`.

Audit commands were read-only Git status/revision/diff/tree/cat-file queries, `rg`/`Get-Content` source/log inspection, `tar -t[v]f`, in-memory Python JSON/tar/hash checks, and `gh run view` metadata/log reads for the run IDs above. No expensive suites or runtime launches were repeated on this Windows auditing host.

The evidence supports macOS 15 ARM64 development and evaluation release acceptance. Clean Mac deployment, Developer ID/notarization, physical presentation, Retina/mixed-monitor behavior, human IME, and screen-reader acceptance remain explicitly disclosed product-release checks, not newly discovered migration regressions. No corrective action is required for this audit partition.
