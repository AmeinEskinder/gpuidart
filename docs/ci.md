# Continuous integration

## Targets and execution scope

| Workflow | Runner | Checks |
| --- | --- | --- |
| Windows SDK checks | Windows Server 2022 x64 | Formatting, analysis, native tests and Dart tests excluding `live-window` |
| macOS SDK checks | macOS 15 ARM64 | Separate headless and native-window jobs; 100k JIT/AOT trace smoke and code reload |
| Linux SDK checks | Ubuntu 24.04 x64 | Separate headless and X11/Xvfb/Openbox/Mesa window jobs; 100k JIT/AOT trace smoke and code reload |
| Unix process lifecycle | macOS 15 ARM64 / Ubuntu 24.04 x64 | Owned process-group cleanup, including orphan and failed exec |
| Unix release packages | Same Unix targets, manual dispatch | Release/AOT packages, extraction/dependency checks, three JIT/AOT baselines per target; Linux runtime-only container |

The [cross-platform evidence](../reports/cross-platform/status.md) records source
revisions and executed test counts. macOS hosted graphics use Apple Paravirtual
Metal; Linux uses software Vulkan. Neither establishes physical presentation or
human IME. Package results and clean desktop/VM checks have separate gates.

## Windows reference

[SDK checks](../.github/workflows/check.yml) runs on pushes, pull requests and manual dispatch in GitHub Actions. It uses Windows Server 2022, Dart 3.13.4 and the Rust version in rust-toolchain.toml. Dependency resolution respects both committed lockfiles. Actions are pinned to commit hashes, and the job has read-only repository permissions.

The job runs `./tool/check.ps1 -Headless`. This checks Rust and Dart formatting, runs native headless tests, analyzes Dart and runs every Dart test except those tagged live-window. The fault DLL still exercises the real FFI callback and runner-isolate lifecycle. The live-window tests require the normal local command without Headless.

The hosted job does not perform GPU window interaction, code reload, AOT packaging, clean-machine verification or human IME checks. Run `./tool/verify_mvp.ps1` on the development Windows desktop for the full local acceptance gate. Clean-machine and human checks remain separate.

The workflow has been checked with actionlint and its Headless command has passed locally. Hosted Windows runs passed at `9c88cd6` and `d463696`; see [the saved CI evidence](../reports/ci/README.md). Results are specific to those source revisions. Hosted images contain development dependencies and cannot establish clean-machine packaging even after a successful job.

Configuration references: [Dart setup action](https://github.com/dart-lang/setup-dart), [MSVC environment action](https://github.com/ilammy/msvc-dev-cmd), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
