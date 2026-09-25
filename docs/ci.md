# Continuous integration

[SDK checks](../.github/workflows/check.yml) runs on pushes, pull requests and manual dispatch in GitHub Actions. It uses Windows Server 2022, Dart 3.13.4 and the Rust version in rust-toolchain.toml. Dependency resolution respects both committed lockfiles. Actions are pinned to commit hashes, and the job has read-only repository permissions.

The job runs `./tool/check.ps1 -Headless`. This checks Rust and Dart formatting, runs native headless tests, analyzes Dart and runs every Dart test except those tagged live-window. The fault DLL still exercises the real FFI callback and runner-isolate lifecycle. The live-window tests require the normal local command without Headless.

The hosted job does not perform GPU window interaction, code reload, AOT packaging, clean-machine verification or human IME checks. Run `./tool/verify_mvp.ps1` on the development Windows desktop for the full local acceptance gate. Clean-machine and human checks remain separate.

The workflow has been checked with actionlint and its Headless command has passed locally. Hosted Windows runs passed at `9c88cd6` and `d463696`; see [the saved CI evidence](../reports/ci/README.md). Results are specific to those source revisions. Hosted images contain development dependencies and cannot establish clean-machine packaging even after a successful job.

Configuration references: [Dart setup action](https://github.com/dart-lang/setup-dart), [MSVC environment action](https://github.com/ilammy/msvc-dev-cmd), [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
