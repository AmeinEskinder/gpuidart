# Windows MVP release candidate

All nine local acceptance checks passed on 2026-09-25. The application is ready for the remaining clean-Windows and human IME checks. The stable-release goal stays open until those results are available.

## Run it

Extract [WatchlistMvp-windows-x64.zip](../../build/WatchlistMvp-windows-x64.zip), keep its files together, and launch WatchlistMvp.exe. It contains the Market watch screen with 1,000 fictitious instruments, search, row selection, a shortlist and incremental price updates. State is in memory.

For development in the repository:

```powershell
dart run tool/dev.dart
```

## Artifact identity

| Item | Value |
| --- | --- |
| Source commit | `8e6940c7c15030ec45499a52a75982985c851561` |
| Source state at packaging | No modified SDK source files |
| ZIP size | 11,485,670 bytes, approximately 10.95 MiB |
| Extracted file size | 30,987,543 bytes, approximately 29.55 MiB, excluding filesystem allocation overhead |
| ZIP SHA-256 | `a90b7c25726a6998eaeb047737912e4bbaf631d38f7a5b4123a97f06bcc7032d` |
| Recorded source SHA-256 | `a3ee3a132a751273e451e17a9fe7f7cb073341bfa8bd87eea23565d74a43db48` |
| Native ABI/protocol | 1 |
| Local OS | Windows 11 Pro, 10.0.26200, x64 |
| Display check | PerMonitorV2, DPI 120 |

The ZIP manifest and [package report](package.json) contain individual file hashes, tool versions, source files and loaded module paths. This is an unsigned evaluation ZIP.

## Acceptance

[acceptance.json](acceptance.json) records every exit code and duration. Each named check has stdout and stderr logs in this directory.

| Check | Result |
| --- | --- |
| Native and Dart | Rust formatting, eight native tests, normal DLL build, Dart analysis with fatal lint information, three Dart/native integration tests and three launcher service-discovery tests passed. |
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

The latest acceptance report and this handoff are saved in the following documentation commit. No subagents were used and no commits were pushed.

## Remaining external checks

The [environment record](environment.json) shows only en-US input, no Windows Sandbox executable, no available VM launcher, no Hyper-V service and a non-elevated process. Local isolated-PATH execution cannot establish a clean machine. Posted characters cannot establish human IME composition.

1. On a clean Windows x64 machine or VM without development SDKs, extract this exact ZIP and run `./verify.ps1 -Environment clean_vm` or `clean_machine`. Retain verification.json, the machine image/prerequisite details and any failure before adding dependencies.
2. With a Japanese, Chinese or Korean IME, complete the composition, candidate placement, commit, cancellation, selection and reload steps in the included RELEASE-CHECKS.md. Record each result and the IME/version.

Return those results against the ZIP hash above. Mixed-monitor DPI movement is additional pending coverage. No stable-release completion is claimed while the two required external checks remain open.
