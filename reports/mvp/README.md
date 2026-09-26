# Windows MVP release candidate

All nine local acceptance checks passed on **2026-09-26** from committed source
`bb6a89425cfb34e03ab0f7a159836712ee921e9c`. This is a release candidate;
human IME and the original unlocalized reload observation remain open.
Clean-Windows launch subsequently passed in a fresh Sandbox with vGPU disabled.
See the [current release record](../release/README.md) for all three
platforms and the post-restart Windows attempt.

## Run it

Extract [WatchlistMit4fca314-windows-x64.zip](../../build/WatchlistMit4fca314-windows-x64.zip)
and launch `WatchlistMit4fca314.exe`. Keep all packaged files together.
The Market watch screen uses typed styles, scoped actions, stable record IDs,
dataset views and declarative cell formatting. Application state is in memory.

For development, run `dart run tool/dev.dart` in the repository.

## Artifact identity

| Item | Value |
| --- | --- |
| Source commit | `4fca3147806878bd3b8fbcff0a92676b8452727e` |
| Source state at packaging | Clean |
| ZIP size | 11,718,871 bytes |
| ZIP SHA-256 | `e5b66c8b3dfafc5af04bd85f56f572acc5bf69a41e2c50b6f823def67476d87b` |
| Recorded source SHA-256 | `d9ca0450e36906542790e7fb91d8aeceba1c08ca93174c32b63d94d794b4b809` |
| Native ABI | 1 |
| Local OS | Windows 11 Pro, 10.0.26200, x64 |
| Display check | PerMonitorV2, DPI 120 |

The [current package report](../release/4fca314/clean-windows/verification.json)
records file hashes, source identity and loaded modules. This unsigned evaluation
ZIP includes the MIT license and UTF-8 verifier fix. Application sources are unchanged from the
nine-check `bb6a894` run. The DLL was rebuilt; its hash differs. Root reports in
this directory retain that earlier full run; [tooling regressions](../release/encoding/README.md)
and the [MIT package milestone](../release/4fca314/README.md) verify the follow-up changes.

## Acceptance

[acceptance.json](acceptance.json) records exit codes and durations. Each check
has stdout and stderr logs in this directory. All nine passed:

1. Formatting, analysis, **41 native and 41 Dart tests**, including live-window tests.
2. Representative watchlist interactions.
3. Input, selection, scrolling, resizing and **500 observed price updates**.
4. Actual code reload, rejected invalid source and recovery with preserved state.
5. Development launcher saved-code reload and shutdown.
6. Development failure deadlines and cleanup.
7. Named AOT package creation with dependency and source identity.
8. Extracted AOT execution outside the repository, with a Windows-only PATH,
   self-test, module identity, Common Controls v6 and DPI checks.
9. Rejection of modified packages and missing explicit self-test success.

These are functional checks. No presentation-latency or new comparative
performance claim follows from them.

## Retained earlier evidence

The [previous root reports](../release/bb6a894/prior-mvp/) were copied before this
run, including their historical handoff and artifact identity. Earlier failed
attempts remain in this directory:

- [Launcher wrapper failure](attempt-1/acceptance.json).
- [Partial VM-service file race](attempt-95481ba/watchlist-ui.stderr.log).
- [Original unlocalized reload mismatch](attempt-023eef4/README.md).
- [Subsequent reload investigation](../reload-investigation/README.md), which
  separately reproduced and fixed a preparation acknowledgement race.

The current pass does not establish the cause of the original reload mismatch.

## Remaining release checks

The [release record](../release/README.md#gates-still-open) tracks the current
human IME, macOS distribution and cross-platform desktop checks. The owner
selected the [MIT License](../../LICENSE) on 2026-09-26.
Japanese typing is installed and enabled after the restart. The initial Sandbox
failed before desktop logon; a fresh software-rendering configuration passed the
package check. [Guest evidence](../release/4fca314/clean-windows/verification.json)
closes clean-Windows launch for this ZIP. Human IME remains unobserved.

Use [Windows release checks](../../docs/windows-release-checks.md) and
[setup instructions](../../docs/windows-test-setup.md) for the observation steps.
Retain failures before adding prerequisites or retrying. The stable-release goal
remains open.

To reproduce automated acceptance from committed source:

```powershell
./tool/verify_mvp.ps1 -Name WatchlistRelease
```

The command replaces root reports. Preserve prior evidence before a new run.
