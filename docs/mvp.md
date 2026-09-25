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
- Milestone 2: host boundary and lifecycle hardened. Seven native tests, three Dart/native tests and Dart analysis passed. See [lifecycle evidence](../reports/sdk/lifecycle.md).
- Milestone 3: bounded launcher startup, process cleanup, named packaging, strict verification and source/build identity completed. See [development and packaging evidence](../reports/sdk/development-packaging.md).
- Milestone 4: all nine local acceptance checks passed from committed source `8e6940c`, including the follow-up startup-race and package-identity fixes. See [the release-candidate record](../reports/mvp/README.md).
- Review follow-up: native panic containment, fallible retained lookups, Dart event validation, request/shutdown deadlines, fault-injection tests and pinned Windows CI were committed. All nine local checks passed again from `5c9a292`, including ten native and 23 Dart tests. [Hosted CI passed](../reports/ci/README.md) through `d463696`. The project license choice remains pending.
- Reload observation: one table-state comparison failed during the first hardening acceptance run. Eight targeted follow-ups and the full rerun passed unchanged assertions. The cause remains unlocalized; [the saved observation](../reports/mvp/attempt-023eef4/README.md) is not discarded.
- Reload investigation: `edffde4` fixed a reproduced preparation-acknowledgement race and added checks after rendering. Twelve native tests, 27 Dart tests and 22 actual code reloads passed. [The investigation](../reports/reload-investigation/README.md) keeps this proved diagnostic bug separate from the original unlocalized failure.
- External release gates: clean Windows environment and human IME results are not available yet.

The latest local acceptance run passed. The stable-release goal remains open pending external evidence and resolution of the reload observation. Testing movement between monitors with different DPI remains additional pending coverage.

## Reproduce local release acceptance

Commit source and test changes, then run:

```powershell
./tool/verify_mvp.ps1
```

This runs nine checks in sequence, records each exit code and log, builds WatchlistMvp-windows-x64.zip, and verifies its source identity. Results are written to reports/mvp/acceptance.json. Any failed check leaves local_acceptance_passed false. The report keeps external release checks pending rather than inferring them from local results.
