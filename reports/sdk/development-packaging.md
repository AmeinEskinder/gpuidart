# Development and packaging hardening

## Launcher

[development.json](development.json) records passing checks for registration delayed until two seconds after the native window opens, subsequent code reload, repeated close, missing reload registration and invalid Dart source. Startup failures left zero test-owned Dart processes running. The no-registration case has a three-second test deadline; production defaults to 30 seconds.

The launcher skips inspection of the isolate blocked in GPUI's native loop and bounds VM-service requests. Its failure cleanup terminates the launched process tree, including Dart's VM child. Closing the application stops file watchers and removes the temporary VM-service directory.

[launcher.json](launcher.json) records a source save in a custom entry directory, the changed native heading, a WM_CLOSE message to the application's actual window, and launcher exit code 0. This verifies the normal Windows close path as well as programmatic shutdown.

## Packaging

[package-candidate.json](package-candidate.json) records successful launch of WatchlistMvp.exe from a temporary directory containing spaces. The application passed its AOT self-test with Windows-only PATH, the intended sibling DLLs, Common Controls v6 and PerMonitorV2 awareness at DPI 120.

The manifest now includes the native ABI, source commit, dirty-source indicator, hashes of source files, tool versions and shipped-file hashes. This build records modified sources honestly. A later release build can point to the completed source commit.

[package-failures.json](package-failures.json) records two rejected packages:

- A changed README failed its package hash check.
- A separate AOT test application opened GPUI and reported mode aot without an explicit boolean passed true. The verifier rejected it.

Both cases started with a stale successful verification report. Each failure replaced that report with passed false and the error. The negative application is confined to the build directory and is not the MVP application.

Reproduce with:

```powershell
dart run tool/verify_dev_failures.dart
dart run tool/verify_dev_launcher.dart
./tool/package.ps1 -Name WatchlistMvp
./tool/verify_package.ps1 -Zip build/WatchlistMvp-windows-x64.zip -ReportPath reports/sdk/package-candidate.json
./tool/verify_package_failures.ps1
```

These are development-machine checks. Clean Windows launch and human IME checks remain open.
