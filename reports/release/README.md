# Current release acceptance

This continues the stable-MVP goal after the feature stack at `bb6a894`.
The public architecture remains snapshots plus retained datasets. No new
runtime feature is part of this release check.

## Work sequence

1. Read the existing work order, skills and acceptance contracts. Completed.
2. Record post-restart Windows prerequisites. Windows servicing reports no
   pending restart. Japanese Basic Typing is installed; Japanese was added
   after English in the current user's language list. Actual Japanese IME use
   subsequently passed the owner-authorized visual checks linked below.
3. All nine Windows release checks passed on committed `bb6a894`: 41 native
   tests, 41 Dart tests, 500 interaction updates, reload, development launcher,
   packaging and failure checks. The package ran at DPI 120 with PerMonitorV2.
4. Both Unix package jobs and the clean-Windows check passed again on `4fca314`
   after MIT licensing. Windows used a fresh Sandbox with GPU sharing disabled. The earlier
   guest desktop crashes and duplicate verifier attempt are retained.
5. The owner selected MIT on 2026-09-26; [LICENSE](../../LICENSE) records the
   terms. Windows Japanese IME checks passed through owner-authorized agent
   observation of real composition, screenshots and actual code reload.
6. Record per-artifact results, remaining gates and a milestone commit.

Success requires current-source release tests and packaging, clean-environment
evidence with artifact identity, and the external observations required by
`docs/mvp.md`. Tests on the earlier cross-platform revision do not establish
release acceptance for the newer feature stack.

Raw evidence is kept in revision-specific directories. The decision log is
`decisions.tsv`. Work is performed without subagents.

## Current evidence

- [Linux desktop VM and Japanese IME observation](../ime/linux-japanese-20260926/README.md): the MIT AOT package passed clean-VM verification and normal search/save/update/close. Configured Fcitx5/Mozc passed composition, editing and actual JIT reload with screenshots and state assertions. Default XIM placement and window-manager restart failures are retained. The observer was an agent; physical display checks remain open.
- [Windows Japanese IME observation](../ime/windows-japanese-20260926/README.md): real preedit, candidate navigation, commit/cancel, editing and active-composition reload passed using the MIT release DLL. The owner requested screenshot/tool verification; the observer was an agent. Interrupted attempts and scope limits are retained.
- [Windows acceptance](bb6a894/windows/acceptance.json), [packaged execution](bb6a894/windows/package.json), [reload](bb6a894/windows/reload.json) and [500-update run](bb6a894/windows/stability.json).
- [MIT package milestone](4fca314/README.md): all three archives include the project license, with matching source and file hashes. All six workflows passed at the implementation commit.
- [Current clean-Windows verification](4fca314/clean-windows/verification.json) passed for the MIT package in a fresh guest without developer SDK commands, at DPI 120 with PerMonitorV2. The corrected `<vGPU>` setting was confirmed by adapter inventory and WARP modules. [The investigation](sandbox-investigation/README.md) retains the compositor crashes and corrects the earlier assumption that `<VGpu>` disabled GPU sharing.
- [Current Unix package workflow](https://github.com/AmeinEskinder/gpuidart/actions/runs/36214976228): extracted macOS/Linux packages, macOS runtime-only verification, X11 geometry at scales 1 and 1.25, and a fresh Ubuntu runtime container passed. [Raw records](4fca314/unix/) retain their individual scope; [earlier evidence](bb6a894/unix/) remains available.
- [Current Windows identity](4fca314/windows-artifact.json): ZIP SHA-256 `e5b66c8b3dfafc5af04bd85f56f572acc5bf69a41e2c50b6f823def67476d87b`. [Current Unix identities](4fca314/unix-artifacts.json) and [previous Windows identity](53ea4c7/artifact.json) are retained separately.
- [PowerShell environment follow-up](powershell-environment/README.md): the new preparation test exposed a hosted Windows module-loading failure. The shared Dart launcher now lets Windows PowerShell rebuild its module path; all 37 local headless tests pass. The hosted failure and unsuccessful local reproduction probes are retained.
- [Post-restart inspection](bb6a894/prerequisites.json) and [Japanese readiness](bb6a894/japanese-readiness.json): no pending restart, Basic Typing installed, Japanese added after English. These are preparation records, not IME observations.
- [Sandbox attempt](bb6a894/sandbox-attempt.json): folder mappings worked; the guest had no logged-in desktop session. The environment later disappeared for an unknown reason. No package result was produced. The desktop inspection helper could not connect after retries and a reset.
- [Language metadata check](language-metadata-check.json): the old PowerShell pipeline produced null fields; explicit iteration reports installed languages correctly. The setup instructions also accept Windows' normalized `ja` tag. [A fresh configuration](bb6a894/sandbox-next-attempt.json) contains the corrected guest script and the same candidate ZIP; it has not been executed.
- [Previous root MVP records](bb6a894/prior-mvp/) were saved before the new acceptance run. Historical failures elsewhere in `reports/mvp/` remain intact.

## Evaluation packages

| Platform | Local artifact | Verified scope |
| --- | --- | --- |
| Windows x64 | [WatchlistMit4fca314-windows-x64.zip](../../build/WatchlistMit4fca314-windows-x64.zip) | MIT license included; local and fresh Sandbox AOT verification, Unicode reports, DLL identity and DPI; confirmed WARP configuration; Japanese IME visually observed on the host |
| macOS ARM64 | [Watchlist-macos-arm64.tar.gz](../../build/evaluation-4fca314/macos/Watchlist-macos-arm64.tar.gz) | MIT license included; hosted macOS 15 execution and packaging |
| Linux x64 | [Watchlist-linux-x64.tar.gz](../../build/evaluation-4fca314/linux/Watchlist-linux-x64.tar.gz) | MIT license included; hosted Ubuntu 24.04 X11, fresh runtime container and clean desktop VM; configured Japanese XIM visually observed |

Archives are build outputs and are not committed to Git. Unix downloads are also
available as artifacts of the workflow linked above. The macOS application/UI
process split remains part of the measured implementation; these runs do not
isolate its cost or establish cross-platform performance rankings.

## Gates still open

| Gate | Required evidence / decision |
| --- | --- |
| Other input/display backends | Windows Japanese IME and configured Linux Fcitx5/Mozc passed by owner-authorized agent observation. macOS IME, AltGr, other IMEs, Retina/physical fractional/mixed-monitor observations remain open. Hosted checks retain their narrower scope. |
| Other desktop launches | Clean macOS observation remains open. Windows Sandbox and Linux desktop VM launch passed; hosted Mac execution retains its narrower scope. |
| Original Windows reload mismatch | The original `attempt-023eef4` remains unlocalized. Passing current checks and the separately proved preparation-race fix do not explain the missing historical values. |
| macOS distribution | Developer ID signing/notarization and a quarantined clean-Mac launch remain pending. Project licensing is resolved as MIT. |

These records establish current automated acceptance and the scoped Windows/Linux IME observations. The stable-release goal
remains open under `docs/mvp.md` and `docs/cross-platform.md`.

The accepted clean-Windows run is
`build/release-checks/20260926-033124-d40b4635`.
Its `results/ime-results.md` remains pending; this guest has only English input.
The separate [host observation](../ime/windows-japanese-20260926/README.md)
closes Windows Japanese IME for the same package; it does not change the guest's
historical observation sheet.
