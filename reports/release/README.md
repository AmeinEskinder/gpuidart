# Current release acceptance

This continues the stable-MVP goal after the feature stack at `bb6a894`.
The public architecture remains snapshots plus retained datasets. No new
runtime feature is part of this release check.

## Work sequence

1. Read the existing work order, skills and acceptance contracts. Completed.
2. Record post-restart Windows prerequisites. Windows servicing reports no
   pending restart. Japanese Basic Typing is installed; Japanese was added
   after English in the current user's language list. Actual IME use is pending.
3. All nine Windows release checks passed on committed `bb6a894`: 41 native
   tests, 41 Dart tests, 500 interaction updates, reload, development launcher,
   packaging and failure checks. The package ran at DPI 120 with PerMonitorV2.
4. Both Unix package jobs passed on `bb6a894`. The clean-Windows check also
   passed in a fresh Sandbox with virtual GPU sharing disabled. The earlier
   guest desktop crashes and duplicate verifier attempt are retained.
5. The owner selected MIT on 2026-09-26; [LICENSE](../../LICENSE) records the
   terms. Complete observed IME checks when a human can perform them.
   Neither an installed input method nor a passing test supplies that evidence.
6. Record per-artifact results, remaining gates and a milestone commit.

Success requires current-source release tests and packaging, clean-environment
evidence with artifact identity, and the external observations required by
`docs/mvp.md`. Tests on the earlier cross-platform revision do not establish
release acceptance for the newer feature stack.

Raw evidence is kept in revision-specific directories. The decision log is
`decisions.tsv`. Work is performed without subagents.

## Current evidence

- [Windows acceptance](bb6a894/windows/acceptance.json), [packaged execution](bb6a894/windows/package.json), [reload](bb6a894/windows/reload.json) and [500-update run](bb6a894/windows/stability.json).
- [Current clean-Windows verification](53ea4c7/clean-windows/verification.json) passed for the UTF-8-corrected package in a fresh guest without developer SDK commands, at DPI 120 with PerMonitorV2. The corrected `<vGPU>` setting was confirmed by adapter inventory and WARP modules. [The investigation](sandbox-investigation/README.md) retains the compositor crashes and corrects the earlier assumption that `<VGpu>` disabled GPU sharing.
- [Unix package workflow](https://github.com/AmeinEskinder/gpuidart/actions/runs/36210888777): extracted macOS/Linux packages, macOS runtime-only verification, three JIT/AOT baseline repetitions per host, X11 geometry at scales 1 and 1.25, and a fresh Ubuntu runtime container passed. [Raw records](bb6a894/unix/) retain their individual scope.
- [Current Windows identity](53ea4c7/artifact.json): ZIP SHA-256 `596b3836de98b5feeb3bc4982b2b6e064400035f7bf29cdfdedeb925e683d27b`. [Earlier archive identities](bb6a894/artifacts.json) retain the previous Windows ZIP and the unchanged Unix packages.
- [PowerShell environment follow-up](powershell-environment/README.md): the new preparation test exposed a hosted Windows module-loading failure. The shared Dart launcher now lets Windows PowerShell rebuild its module path; all 37 local headless tests pass. The hosted failure and unsuccessful local reproduction probes are retained.
- [Post-restart inspection](bb6a894/prerequisites.json) and [Japanese readiness](bb6a894/japanese-readiness.json): no pending restart, Basic Typing installed, Japanese added after English. These are preparation records, not IME observations.
- [Sandbox attempt](bb6a894/sandbox-attempt.json): folder mappings worked; the guest had no logged-in desktop session. The environment later disappeared for an unknown reason. No package result was produced. The desktop inspection helper could not connect after retries and a reset.
- [Language metadata check](language-metadata-check.json): the old PowerShell pipeline produced null fields; explicit iteration reports installed languages correctly. The setup instructions also accept Windows' normalized `ja` tag. [A fresh configuration](bb6a894/sandbox-next-attempt.json) contains the corrected guest script and the same candidate ZIP; it has not been executed.
- [Previous root MVP records](bb6a894/prior-mvp/) were saved before the new acceptance run. Historical failures elsewhere in `reports/mvp/` remain intact.

## Evaluation packages

| Platform | Local artifact | Verified scope |
| --- | --- | --- |
| Windows x64 | [WatchlistRelease53ea4c7-windows-x64.zip](../../build/WatchlistRelease53ea4c7-windows-x64.zip) | Local and fresh Sandbox AOT verification, Unicode reports, DLL identity and DPI; confirmed WARP configuration |
| macOS ARM64 | [Watchlist-macos-arm64.tar.gz](../../build/evaluation-bb6a894/macos/Watchlist-macos-arm64.tar.gz) | Hosted macOS 15 execution and packaging |
| Linux x64 | [Watchlist-linux-x64.tar.gz](../../build/evaluation-bb6a894/linux/Watchlist-linux-x64.tar.gz) | Hosted Ubuntu 24.04 X11 and fresh runtime container |

Archives are build outputs and are not committed to Git. Unix downloads are also
available as artifacts of the workflow linked above. The macOS application/UI
process split remains part of the measured implementation; these runs do not
isolate its cost or establish cross-platform performance rankings.

## Gates still open

| Gate | Required evidence / decision |
| --- | --- |
| Human IME | Observed preedit, candidate placement, commit/cancel, selection and reload, with input method/version. Installed Japanese and injected Unicode do not satisfy this. |
| Other desktop backends | Clean Mac launch, human IME on each supported backend, Retina/fractional/mixed-monitor observations. Hosted checks retain their narrower scope. |
| Original Windows reload mismatch | The original `attempt-023eef4` remains unlocalized. Passing current checks and the separately proved preparation-race fix do not explain the missing historical values. |
| macOS distribution | Developer ID signing/notarization and a quarantined clean-Mac launch remain pending. Project licensing is resolved as MIT. |

These records establish current automated acceptance. The stable-release goal
remains open under `docs/mvp.md` and `docs/cross-platform.md`.

The accepted clean-Windows run is
`build/release-checks/20260926-025749-1ad11737`.
Its `results/ime-results.md` remains pending; this guest has only English input.
Human Japanese IME checks must use the prepared host or another machine with
the input method installed.
