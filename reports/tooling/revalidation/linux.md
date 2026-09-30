# Linux migration audit: PASS

Native audit of final HEAD `a2600907a8013a5e890ce9c23c248f02f5f6887c` and implementation source `d02a4ce7b6b317d0115ba7dac344e6b22e775eb4`, performed 2026-09-30. No material migration blocker found in the assigned Linux runtime, GPUI/cache, lifecycle, packaging or Linux CI scope. This replaces the failed external Grok audit attempt; it does not represent a successful Grok review.

## Revision and evidence integrity

`git status --short` was empty; `git rev-parse HEAD` returned the final SHA above. `git diff --stat d02a4ce7b6b317d0115ba7dac344e6b22e775eb4 a2600907a8013a5e890ce9c23c248f02f5f6887c` showed only documentation and retained evidence changes. The platform probe's raw `source.stdout.log` contains the implementation SHA. Exact file hashes matched between committed and raw reports for Linux cache events, platform probe, release package verification, fresh container verification and compiled CLI reload.

Queried GitHub directly with `gh run view ID --repo AmeinEskinder/gpuidart --json headSha,conclusion,url,jobs`. All relevant jobs were successful at the expected SHA:

| Run | Scope | SHA |
| --- | --- | --- |
| 36656530640 | Linux headless and window | d02a4ce7 |
| 36656530692 | Unix lifecycle, including Ubuntu | d02a4ce7 |
| 36656535626 | Accessibility, including Ubuntu | d02a4ce7 |
| 36656530729 | Platform probe, including Ubuntu | d02a4ce7 |
| 36656530668 | Release packages, including Ubuntu | d02a4ce7 |
| 36658300630 | Final HEAD Linux headless and window | a2600907 |
| 36658300539 | Final HEAD Unix lifecycle | a2600907 |

## Runtime, native input and reload

- The raw source Linux SDK log establishes 115 passing native tests with one deliberately ignored timing probe (`.cache/migration-completion/validated-final/linux-sdk/run.log:1537`), 3 snapshot tests (`:1555`), clean Dart analysis (`:1564`), 9 benchmark analysis tests (`:1583`), and 116 passing headless Dart tests with two skips (`:1731`). The window job records 29 passing tests (`:3350`), settings JIT/AOT verification with 15 steps each (`:3351`), and both 100,000-row JIT/AOT tracing checks (`:3353`). Reload explicitly preserved application state, text/focus/selection, table identity and scroll without republishing data (`:3357`).
- X11 input is real OS injection: `tool/platform_probe/run.dart:347` uses PID/title-scoped `xdotool` search, activation, typing and click; `.github/workflows/platform-probe.yml` enables `GPUIDART_PROBE_INPUT=1` on Linux. `tool/platform_probe/run.dart:180` requires a resized-render checkpoint and input/click checkpoints. The Rust probe also gates successful return on those results (`tool/platform_probe/native/src/lib.rs:392`). The raw/retained log (`reports/tooling/completion/linux-native-input.log:16`) shows matching typed text, one click, resize from 640x360 to 720x420, a rendered resized frame and successful loop return. This is stronger than a window-open-only assertion.
- `reports/tooling/completion/platform-Linux-X64.json` records successful native main and worker, Dart JIT/AOT, companion JIT/AOT and both reload paths, with no timeout or input-driver error. Raw `display.stdout.log:1` proves `xrandr --verbose` observed the 1280x800 X11 display; the workflow explicitly installs `x11-xserver-utils`.
- Raw `platform/platform-probe-Linux-X64/reload.json` records unchanged native PID and input entity/value across reload, invalid-source rejection, recovery and exit 0. `reload-ffi.json` records callback change 7 to 8 in the same process, invalid-source rejection and recovery.
- `reports/tooling/completion/cli-reload-Linux-X64.json:1` proves the compiled CLI reloaded a custom entry after file save and stopped after native-window close, exit 0.

## GPUI and AT-SPI cache

- The current implementation is Dart orchestration and Rust external native API probing: `tool/accessibility/cache_events.dart` launches the compiled native probe and waits for readiness; `tool/native_probe/src/linux/cache.rs:143` resolves the signal sender's PID, filters it to the target, validates one structured argument (`:162`), and performs a D-Bus round trip after subscription before reporting ready (`:224`). Passing requires positive add and remove counts, no invalid payloads and no error (`:280`).
- The AccessKit patch emits single tuple arguments for both cache signals (`native/vendor/accesskit_unix-0.22.1/src/atspi/bus.rs:399` and `:410`), matching the documented `native/vendor/cache-signals.patch` and the observer's expected signatures.
- The raw `accessibility/accessibility-Linux-X64/controls.json.cache-events.json:1`, identical to `reports/tooling/completion/linux-cache-events.json`, records 50 additions, 47 removals, zero invalid events and PASS for PID 6131. The enclosing controls report preserves this result. Source inspection shows counts cannot pass with no matching events.
- Underlying Linux accessibility reports all pass: controls, disabled controls, platform spike, settings, watchlist, terminal JIT/AOT and terminal reload. Inspected controls steps include external toggle, range write, modal cancellation and confirmation; watchlist covers bounded semantics for 100k rows, external row selection, incremental prices and preserved identity during filtering/sorting.

## Native artifacts, package provenance and fresh runtime

- `.github/workflows/release-packages.yml:67` compiles the CLI; `:79` uses that executable for package construction; `:110` uses it to verify Linux extraction. `tool/build_cli.dart:19` compiles `bin/gpuidart.dart` to a native executable. The retained CLI tar contains an executable `gpuidart` of 8,200,056 bytes. Read its bytes through `tar -xOf` without extraction: ELF magic `7F-45-4C-46`, class 2 (64 bit), machine 62 (x86-64).
- Independently recomputed archive SHA-256: `Watchlist-linux-x64.tar.gz` = `927db5c72ec678c1d5277f0264f88edf8a3e074c72c8bb5c5b7e0940fc186529`; CLI tar = `4499faece490542d1fcaa55bfeff3e03c2c9cc71ce2cb76c4430624dabf62580`. The release archive matches its verification report.
- Parsed the embedded `./manifest.json` using `tar -xOf`: it exactly matches the report manifest, declares `source_dirty=false`, implementation SHA `d02a4ce7...`, and source digest `78ef343614b15de1a31c134c25f9268a0d7760ed06ab189015630ad9f6b23aca`. Streamed all 15 listed payload files directly from the tar through .NET SHA-256; every hash matched. Executable modes are retained for Watchlist, native library, launcher and verifier. Licenses and notices are present.
- `reports/tooling/completion/package-Linux-X64.json:1` records extracted AOT launch, exit 0, 1,000 rows, actual 960x720 native window, clean stderr, restricted system PATH, and loaded Watchlist/library paths from the extracted directory. All four `ldd` inspections exit 0 without unresolved dependencies.
- `tool/unix/Dockerfile.runtime:1` starts from Ubuntu 24.04, installs runtime/display packages, copies only the built archive and asserts that `dart`, `rustc` and `cargo` are absent (`:12`). Workflow `release-packages.yml:125` creates and runs this image. Raw container image metadata records image `sha256:6e51fab4174ceb3f59326e8d177c6893238c6d9b19935fc117f5fb3af7304cbc`; package inventory contains no Dart/Rust toolchain. `reports/tooling/completion/linux-clean-container.json:1` records successful AOT native-window launch from `/evaluation/extracted`, all dependencies resolved and exit 0. Its `runtime_only=false` refers to verifier mode with `ldd` available; it does not imply developer toolchains were installed.
- Forced X11 scale reports prove physical/logical geometry: scale 1 has 960x720 then 800x600; scale 1.25 has physical 1200x900 then 1000x750 while native logical dimensions remain 960x720 then 800x600 (`reports/tooling/completion/linux-scale-1.json:1`, `linux-scale-1.25.json:1`).

## Unix lifecycle and limits

`launcher/src/main.rs:40` creates an owned Unix session using `setsid`; `tool/src/owned_process.dart:37` terminates its process group, escalates after a deadline and sweeps after parent exit. `test/owned_process_test.dart` checks interruption during startup/watching, a TERM-ignoring descendant after parent exit, idempotent stop and bounded exec failure. The raw Ubuntu lifecycle log records all 7 tests passing (`.cache/migration-completion/validated-final/lifecycle/run.log:173`).

No expensive suites were rerun. This Windows-hosted audit inspected actual Linux hosted logs, compiled artifacts, source and live GitHub metadata; it did not locally launch Linux binaries. X11 rendering uses Xvfb and Mesa llvmpipe, so this audit adds no physical-monitor, hardware-GPU, Wayland, mixed-monitor or IME claim. The scale reports explicitly say this. Pinned AT-SPI EditableText absence is disclosed in raw controls (`controls.json:2648`) and watchlist (`watchlist.json:6098`); those text changes use GPUI diagnostic keys followed by external AT-SPI reads, while the separate platform probe establishes actual X11 typing. This is a pre-existing adapter limitation, not a remaining tooling migration blocker. Existing timing skips and recorded Clippy warnings are not represented as eliminated.

Commands examined/executed: `git status --short`; `git rev-parse HEAD`; the exact two-SHA `git diff --stat` above; scoped `rg`/`Get-Content` reads of workflows, source and raw evidence; `gh run view` for all seven listed run IDs; `tar -tvzf` for both Linux archives; `tar -xOf` for embedded manifest and all payload entries; `Get-FileHash -Algorithm SHA256` for archives and retained/raw report comparisons; .NET SHA-256 over tar stdout for all 15 payload hashes and direct ELF-header inspection. No repository implementation, documentation or committed evidence was changed.
