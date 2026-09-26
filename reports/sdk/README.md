# Windows SDK preview verification

Recorded on 2026-09-25 in the working tree. GPUI-Dart 0.1 now has a documented application contract, a reusable development launcher and a packaged representative screen. Whole-view snapshots, retained datasets and the existing Dart-to-Rust bridge remain the application architecture.

## Delivered

- [Market watch](../../example/watchlist/main.dart) displays 1,000 fictitious instruments with search, row selection, a shortlist, price sorting and sample price edits. A price or shortlist edit publishes one cell; search and filtering are a native view that never republishes records, and selection survives view changes by record ID. Application state is in memory.
- [The SDK guide](../../docs/sdk.md) documents lifecycle, IDs, dataset revisions, errors, reload and packaging. New public APIs cover row layout, initial window options, typed table-selection events and shared development reload registration.
- The development launcher accepts an entry point and application arguments, watches that entry point's directory and lib, applies saved code changes, and exits after the window closes.
- The shared Windows host selects or verifies PerMonitorV2 awareness. The AOT executable also embeds that setting in its application manifest.
- Packaging accepts a custom entry point and application filename. The ZIP includes DLLs, file hashes, a standalone verifier and manual release checks.

## Package

[gpuidart-windows-x64.zip](../../build/gpuidart-windows-x64.zip) contains the Market watch AOT application.

| Item | Value |
| --- | --- |
| ZIP bytes | 11,482,799, approximately 10.95 MiB |
| Extracted file bytes | 30,966,050, approximately 29.53 MiB, excluding filesystem allocation overhead |
| ZIP SHA-256 | `39ba9ec868642b1dc2c488cfe51db3688e4cbec96af1aef9fa524d62017792c5` |
| Target | Windows x64 |
| Local verification OS | Windows 11 Pro, 10.0.26200 |
| GPUI Kit revision | `21622a70efd25219d26aa459164878c4da9e39f8` |

This is an unsigned evaluation ZIP built from an uncommitted working tree. The package manifest and [verification report](package.json) identify the exact executable and DLL hashes. It has not been published as a stable SDK or installer.

## Completed checks

| Check | Result and evidence |
| --- | --- |
| Native and Dart checks | `./tool/check.ps1` passed Rust formatting, seven native tests, the normal debug DLL build, Dart analysis and one Dart/native integration test. Final `dart analyze` also passed after adding the launcher verification. |
| JIT screen self-test | `dart run example/watchlist/main.dart --self-test` passed search, selection, cell updates, shortlist filtering/removal and restoring 1,000 records. |
| Live UI messages | [interaction.json](interaction.json) passed search, row selection, saving, a price change to 100.07 and shortlist filtering. The same script also checked typing and immediately clearing a query, leaving all 1,000 records visible. It used posted Windows messages. |
| Actual code reload | [reload.json](reload.json) records changed heading code executing in the same application process and isolate. Query ALP, selected instrument ALP0200, one price update, native input text/focus/selection, table entity and scroll position survived. Dataset publication bytes remained 5,564 before and after reload. Invalid source was rejected while the previous code remained live. |
| Legacy example reload | `dart run tool/verify_reload.dart` passed after migrating the example to the shared reload helper. See [reload.json](../reload.json). |
| Development launcher | [launcher.json](launcher.json) records a custom entry directory, automatic reload after saving the source, and launcher exit code 0 after closing the application. |
| AOT package | [package.json](package.json) passed the screen self-test from an extracted temporary directory, with Windows as its working directory and only Windows directories on PATH. It verified file hashes, the sibling GPUI/CRT DLLs, Common Controls v6, and the absence of loaded Dart SDK/Flutter modules. |
| Production DPI | The packaged window reported PerMonitorV2 and DPI 120. A 960 by 720 logical client area occupied 1,200 by 900 physical pixels. See [window.json](visual/window.json). |
| Visual inspection | [Initial screen](visual/watchlist.png) and [selected, saved and updated row](visual/watchlist-edited.png) were inspected at 125% scaling. The full client area was visible without clipped controls at the initial window size. |
| Diff hygiene | `git diff --check` passed. Git reported line-ending conversion notices. |

The launcher verification initially stalled because its probe requested details from the isolate blocked in the native UI loop. The probe now stops after finding the application isolate. The completed launcher result above includes an actual source-file save and observed native heading change.

To reproduce the SDK checks, use the commands in the [SDK guide](../../docs/sdk.md#verification-status). The UI and reload scripts retain their source copies under .cache.

## Remaining release checks

- Clean-machine dependency closure remains unverified. The restricted-PATH test ran on the development machine. No Windows Sandbox executable or available VM launcher was found here.
- Human IME composition remains unverified. This computer has only the US English input method. Posted Unicode or character messages cannot establish composition, candidate placement, commit or cancellation behavior.
- Human resizing, scrolling and keyboard interaction, plus moving between monitors with different display scales, still need the [manual release checks](../../docs/windows-release-checks.md).
- Input-to-present latency remains unmeasured. Diagnostic timing fields in the verification JSON are incidental samples, with no correlated presentation evidence.

The [completed Dart/Solid/Shell comparison](../comparison/dart-js-20260925.md) retains its original captures and hashes. This SDK work rebuilt the native library and application. These functional checks do not constitute new comparative performance measurements.
