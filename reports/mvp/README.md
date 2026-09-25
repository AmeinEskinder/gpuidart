# Windows MVP release candidate

All nine local acceptance checks passed on 2026-09-25 after boundary hardening. Clean-Windows and human IME checks remain pending. One earlier reload table-state mismatch remains unlocalized despite subsequent passing runs. The stable-release goal stays open.

## Run it

Extract [WatchlistMvp-windows-x64.zip](../../build/WatchlistMvp-windows-x64.zip), keep its files together, and launch WatchlistMvp.exe. It contains the Market watch screen with 1,000 fictitious instruments, search, row selection, a shortlist and incremental price updates. State is in memory.

For development in the repository:

```powershell
dart run tool/dev.dart
```

## Artifact identity

| Item | Value |
| --- | --- |
| Source commit | `5c9a2929e5de9bafd4d9788d385fc5b60b240fe0` |
| Source state at packaging | No modified SDK source files |
| ZIP size | 11,499,504 bytes, approximately 10.97 MiB |
| Extracted file size | 31,012,351 bytes, approximately 29.58 MiB, excluding manifest and filesystem allocation overhead |
| ZIP SHA-256 | `c86aa402e49dbd480e829e2497d6793ad9d2d4034bff50bcfc7a2adb4b14ea12` |
| Recorded source SHA-256 | `58d47219c116bf296118e13e82a3ecfcb7a3d9fe788e6acb13a07d1f46d87024` |
| Native ABI/protocol | 1 |
| Local OS | Windows 11 Pro, 10.0.26200, x64 |
| Display check | PerMonitorV2, DPI 120 |

The ZIP manifest and [package report](package.json) contain individual file hashes, tool versions, source files and loaded module paths. This is an unsigned evaluation ZIP.

## Acceptance

[acceptance.json](acceptance.json) records every exit code and duration. Each named check has stdout and stderr logs in this directory.

| Check | Result |
| --- | --- |
| Native and Dart | Formatting, ten native tests, normal DLL build, Dart analysis with fatal lint information and 23 Dart tests passed. Coverage includes the live GPUI window, FFI fault injection, pure Dart models/event decoding and launcher service discovery. |
| Representative UI | Search, rapid typing/clearing, row selection, shortlist actions and price edits passed through the live window. |
| Interaction stability | Keyboard navigation, table scrolling, Unicode text and emoji deletion, narrow-window scrolling and restoring window size passed. All 500 price updates were observed. |
| Code reload | Eleven successful reloads preserved state. Invalid source was rejected and later valid source recovered. Reload transferred no table records. |
| Development launcher | Saving a custom entry's source changed the native heading. WM_CLOSE ended the application and launcher with exit code 0. |
| Development failures | Delayed registration worked. Missing registration and invalid source failed within the test deadline and left no test-owned Dart processes. |
| AOT build | Named application, native DLL, CRT, DPI manifest, source identity and standalone verifier packaged successfully. |
| AOT launch | Extracted outside the repository into a path containing spaces. Windows-only PATH, application self-test, DLL paths, Common Controls v6 and DPI checks passed. |
| Verification failures | Changed package contents and a missing explicit self-test success were rejected. Failed verification replaced stale success reports. Named release instructions and identity for an ignored application entry were also checked. |

The [first acceptance attempt](attempt-1/acceptance.json) passed the native/Dart check and then failed to launch Dart. The runner had treated this machine's Flutter batch wrapper as an executable path. Commit 739bd18 resolves the actual Dart executable through the installed launcher. The full repeated gate above passed after that fix.

The first completed candidate remains available as [source-739bd18 acceptance](source-739bd18/acceptance.json) and [its archived ZIP](../../build/WatchlistMvp-739bd18-windows-x64.zip). A follow-up audit found two packaging gaps: custom executable names were absent from the included release instructions, and ignored application entry files were absent from source hashes. Both are fixed and checked in the latest gate.

The [95481ba attempt](attempt-95481ba/acceptance.json) exposed a real startup race. The launcher observed the VM-service file after creation but before Dart completed its JSON write, then failed to parse the empty file. Startup now waits for a complete service URI within its existing deadline. Three focused tests cover empty/partial writes, process exit before readiness, and the deadline. The latest full gate passed after this fix. See [the saved failure log](attempt-95481ba/watchlist-ui.stderr.log).

The previous candidate is preserved in [source-8e6940c](source-8e6940c/acceptance.json) with [its ZIP](../../build/WatchlistMvp-8e6940c-windows-x64.zip). Boundary hardening added caught Rust unwinds, fallible retained-state lookups, validated immutable native events and request/shutdown deadlines. [Failure handling](../../docs/failures.md) states the recovery limits. [Hosted CI](../ci/README.md) subsequently passed at `9c88cd6` and `d463696`; these jobs exclude desktop interaction and packaging.

The [023eef4 attempt](attempt-023eef4/README.md) failed at the reload table-state comparison after the other interaction checks passed. The old verifier omitted the differing values. Seven isolated repetitions and one stability-then-reload repetition passed all eleven reloads each; the full gate above then passed. The observation remains unresolved. The verifier now saves before/after state and the latest repeated-reload state on failure. Its checks and timing were not relaxed, and no production reload change was made to obtain the later passes.

A [subsequent investigation](../reload-investigation/README.md) fixed a reproducible diagnostic preparation race in `edffde4` and added state checks after rendering. That change is newer than this packaged candidate. It does not establish the cause of the original failure.

Interaction failures and their fixes are retained in [the stability record](../sdk/interaction-stability.md). Screenshots show the [narrow window](../sdk/visual/watchlist-small.png), [reachable footer](../sdk/visual/watchlist-footer.png) and [edited row](../sdk/visual/watchlist-edited.png).

Reproduce after committing source/test changes:

```powershell
./tool/verify_mvp.ps1
```

The gate builds a new artifact and overwrites the latest acceptance report. Preserve an earlier ZIP and report before comparing builds. Publication and drawing samples in the functional reports do not establish input-to-present latency. Historical comparative benchmark conclusions remain unchanged.

## Commits saved during this goal

| Commit | Milestone |
| --- | --- |
| `a1f679b` | Saved the completed benchmark series and SDK preview. |
| `651e793` | Hardened native compatibility, startup cleanup and shutdown with pending work or paused subscribers. |
| `af9ff34` | Hardened launcher startup/cleanup and AOT packaging/verification. |
| `132a40f` | Fixed narrow-window layout and added sustained interaction/reload evidence. |
| `b23ccad` | Added the committed-source acceptance command. |
| `739bd18` | Fixed executable resolution for Dart launch wrappers. |
| `baa03dd` | Saved the first candidate's acceptance evidence and release handoff. |
| `95481ba` | Corrected named release instructions and included ignored/external entry files in package identity. |
| `8e6940c` | Fixed the partial VM-service-file startup race and added focused regression tests. |
| `625ad01` | Contained Rust unwinds at FFI exports, replaced retained-map indexing and tested exported functions. |
| `38d72a0` | Added Dart protocol validation, bounded requests/shutdown and FFI fault-injection tests. |
| `023eef4` | Added pinned Windows CI and clarified historical report scope. |
| `5c9a292` | Saved the failed reload observation and added failure-state capture. |

The latest acceptance report and this handoff are saved in the following documentation commit. No subagents were used and no commits were pushed.

## Remaining external checks

The [Windows test setup](../../docs/windows-test-setup.md) now prepares this exact
candidate for an automatic Sandbox run and provides the administrator setup
command for Sandbox and Japanese input. Its generated IME sheet records actual
observations separately. These checks remain pending until their results exist.

The [new preparation record](release-check-preparation.json) identifies the rebuilt
ZIP and `build/release-checks/20260925-182232-410072f0/check.wsb`. Its input ZIP hash
matches the artifact above. Use this preparation for the new candidate; earlier
prepared folders contain older ZIPs. Preparation does not count as execution.

The administrator setup enabled the Sandbox feature. After the connection became
unmetered, DISM staged Japanese typing with `InstallPending` and requested a
restart; fonts remained uninstalled. The [diagnosis and revised setup checks](prerequisites/README.md)
record the progress and recovery steps. Those records and the earlier environment
record below predate this rebuilt ZIP. No restart or further installation was
initiated during boundary hardening.

The [environment record](environment.json) shows only en-US input, no Windows Sandbox executable, no available VM launcher, no Hyper-V service and a non-elevated process. Local isolated-PATH execution cannot establish a clean machine. Posted characters cannot establish human IME composition.

1. On a clean Windows x64 machine or VM without development SDKs, extract this exact ZIP and run `./verify.ps1 -Environment clean_vm` or `clean_machine`. Retain verification.json, the machine image/prerequisite details and any failure before adding dependencies.
2. With a Japanese, Chinese or Korean IME, complete the composition, candidate placement, commit, cancellation, selection and reload steps in the included RELEASE-CHECKS.md. Record each result and the IME/version.

Return those results against the ZIP hash above. Mixed-monitor DPI movement is additional pending coverage. The project license also awaits the owner's choice; the bundled GPUI Kit license does not license this SDK's own code. No stable-release completion is claimed while the external checks and unresolved reload observation remain open.
