# Windows MVP acceptance

The MVP supports one Windows x64 application window, Dart application state, native inputs and tables, whole-view snapshots, retained datasets, JIT code reload and AOT ZIP distribution. The Market watch screen is the representative application. General node mutations, other platforms and presentation-latency claims are outside this milestone.

## Milestones

1. Save the completed benchmark series and SDK preview, including their raw evidence.
2. Harden the host boundary. Reject incompatible DLLs before starting native code, preserve cleanup on startup failure, reject unsupported concurrent hosts, and verify shutdown with pending work.
3. Harden development and packaging. Verify launcher startup failures, saved-code reload and shutdown; verify a named AOT package outside the repository with a strict self-test contract and source/build identity.
4. Exercise the release candidate. Run native and Dart checks, repeated application interactions and reload, UI sizing/navigation and AOT verification. Save an acceptance report and commit the completed work.

Each completed milestone gets a local Git commit. Existing benchmark captures remain historical evidence; SDK changes do not inherit their performance results.

## Release evidence

Local acceptance requires passing analysis, native and Dart tests, actual UI interactions, code reload with preserved state, and packaged execution with the intended DLLs and DPI settings. Failures must remain recorded and explained.

Clean-machine launch and human IME composition require separate evidence under [Windows release checks](windows-release-checks.md). A development-machine PATH restriction is not clean-machine proof. Character injection is not IME proof. Until those checks pass, describe the artifact as an MVP release candidate and identify these open release gates.

## Progress

- Milestone 1: benchmark series and SDK preview completed. See [comparison](../reports/comparison/dart-js-20260925.md) and [SDK verification](../reports/sdk/README.md).
- Milestones 2 through 4: in progress.
- External release gates: clean Windows environment and human IME results are not available yet.
