# Continuous integration

## Targets and execution scope

| Workflow | Runner | Checks |
| --- | --- | --- |
| Windows SDK checks | Windows Server 2022 x64 | Formatting, analysis, native tests and the full Dart suite including live windows |
| macOS SDK checks | macOS 15 ARM64 | Separate headless and native-window jobs; settings JIT/AOT verifier, 100k JIT/AOT trace smoke and code reload |
| Linux SDK checks | Ubuntu 24.04 x64 | Separate headless and X11/Xvfb/Openbox/Mesa window jobs; settings JIT/AOT verifier, 100k JIT/AOT trace smoke and code reload |
| Unix process lifecycle | macOS 15 ARM64 / Ubuntu 24.04 x64 | CLI interruption during startup and watching; owned process-group cleanup, including orphan and failed exec |
| Release packages | Windows Server 2022 x64, macOS 15 ARM64, Ubuntu 24.04 x64 | Native CLI and release/AOT packages, extracted package verification and compiled CLI reload; Unix JIT/AOT baselines and Linux runtime-only container |

The [cross-platform evidence](../reports/cross-platform/status.md) records source
revisions and executed test counts. macOS hosted graphics use Apple Paravirtual
Metal; Linux uses software Vulkan. Neither establishes physical presentation or
human IME. Package results and clean desktop/VM checks have separate gates.

## Windows reference

[SDK checks](../.github/workflows/check.yml) runs on pushes, pull requests and manual dispatch in GitHub Actions. It uses Windows Server 2022, Dart 3.13.4 and the Rust version in rust-toolchain.toml. Dependency resolution respects both committed lockfiles. Actions are pinned to commit hashes, and the job has read-only repository permissions.

The SDK jobs compile the native CLI, then invoke `gpuidart check`. Windows runs the full suite; Unix headless jobs pass `--headless` and separate window jobs cover the graphical tests. The gate checks Rust and Dart formatting, runs native tests, analyzes Dart, rebuilds a CLI under `build/check` and runs its doctor, and runs Dart tests. Keeping the test executable separate lets the running CLI verify itself. The fault DLL exercises the real FFI callback and runner-isolate lifecycle.

The separate [release workflow](../.github/workflows/release-packages.yml) builds native CLI executables and packages on all three targets. It drives packaging, extraction verification and code reload through the compiled CLI, then retains the binaries and reports. Run `dart run tool/verify_mvp.dart` on the development Windows desktop for local acceptance. Hosted development images do not establish clean-machine launch or human IME behavior.

All seven migration workflows passed at `d02a4ce`, including the full Windows gate, both Unix SDK jobs, accessibility, platform probes, process lifecycle, and three-platform release packaging. The [migration completion report](../reports/tooling/completion.json) retains run links, test counts, artifact hashes, and package reports. Actionlint and the actual compiled Windows CLI full check also passed locally. The [earlier Windows CI record](../reports/ci/README.md) preserves historical runs. Results are specific to their source revisions. Hosted images contain development dependencies; the separate Linux runtime container verifies launch without Dart or Rust SDKs.

Configuration references: [Dart setup action](https://github.com/dart-lang/setup-dart), [MSVC environment action](https://github.com/ilammy/msvc-dev-cmd), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
