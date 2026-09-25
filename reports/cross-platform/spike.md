# Cross-platform execution record

Work order: [cross-platform.md](../../docs/cross-platform.md). Starting source:
`c543e71`. This record tracks implementation and acceptance separately. The goal
service still holds the unfinished Windows MVP goal and rejected replacement;
this file tracks the explicitly requested cross-platform objective meanwhile.

## Targets and available environments

| Candidate target | Environment | Initial display scope | Status |
| --- | --- | --- | --- |
| macOS 15, ARM64 | GitHub `macos-15` | Hosted Metal window; manual input access pending | Untested |
| Ubuntu 24.04, x64, glibc 2.39 | GitHub `ubuntu-24.04` | X11 with Xvfb and Mesa software Vulkan | Untested |
| Linux through WSL2 | Existing Podman VM, disposable project container | WSLg availability to be probed | Untested |
| Windows x64 reference | Local desktop and `windows-2022` | Existing Windows backend | Latest hosted source `e8a176a` passed |

These are candidates, not support claims. macOS versions before 15, Intel Macs,
other Linux libc/distributions and native Wayland remain outside the initial
declared scope. Runtime probes must record actual OS, architecture, renderer,
display and scaling before a result can be accepted. Software rendering cannot
establish hardware rendering, physical presentation or human input behavior.

## Execution and acceptance checklist

- [ ] Phase 0: pinned Rust example, native thread ownership, window rendering,
  resize, input and shutdown on each target.
- [ ] Phase 0: Dart JIT/AOT launcher, callbacks and application event loop;
  VM-service discovery, reload and close/lifetime evidence for chosen strategy.
- [ ] Phase 1: implement only the launch strategies proven above; port clocks,
  loaders, fixtures and process cleanup. Preserve the Windows contracts.
- [ ] Phase 2: display/scaling checks and retained human IME observations.
- [ ] Phase 3: portable build/check/package, hosted headless and window jobs,
  extracted package dependencies and actual loaded libraries.
- [ ] Phase 4: common behavioral suites, 100k JIT/AOT traces, actual reload,
  clean-environment launch, human checks and defined startup/memory baselines.

Every completed milestone receives a commit and evidence. Failed attempts stay
recorded. Production host code remains unchanged until its Phase 0 strategy is
proven. Changes to the dependency pin require renewed Windows acceptance.

## Independent release gates

Windows clean-machine launch, human IME, the original unlocalized reload
observation and owner license selection remain open. Hosted build images are
not clean consumer machines. The current packaged Windows candidate is retained
unchanged while the platform probes run.

## Probe scope

`tool/platform_probe/` is isolated from the SDK host. Its window starts from the
pinned toolkit's hello-world example, adds an input and bounded lifetime, and
reports OS thread ownership at the executable, FFI call and UI callback. Render
callbacks and window-size changes establish native UI execution only; they do
not establish physical presentation. Input injection and human input are
separate checks. A macOS FFI call on a non-main thread is rejected before AppKit
is entered.

## Windows verification of the probe

Before the first probe commit, all four launch variants passed on the Windows
desktop: Rust main thread, Rust worker, Dart JIT and Dart AOT. All rendered at the
requested resized viewport and returned normally. Both Dart modes received the
ready and echo callbacks while the application timer ran. The final run applied
the SDK DPI setting and reported scale 1.25 in all variants. See
[the raw result](windows-dpi/results.json) and adjacent command logs.

The first failed JIT/AOT run is retained in [windows-initial](windows-initial/results.json).
It failed while sending the probe's captured async context to the isolate, before
calling GPUI. `tool/platform_probe/README.md` records this and the development
compile/manifest fixes. The source SHA in these pre-commit logs identifies the
base revision; the probe code was uncommitted during these checks.

Windows preservation checks passed: 12 native tests, 27 Dart tests including the
five live-window cases, Cargo formatting and Dart analysis. These checks do not
complete any macOS/Linux acceptance item.

## First hosted probe, source `ac7aed4`

[Run 36181630595](https://github.com/AmeinEskinder/gpuidart/actions/runs/36181630595)
built the pinned dependency on both targets. Raw logs are retained under
`hosted-initial/`; [run metadata](run-36181630595.json) records the source and jobs.

| Check | Ubuntu 24.04 x64, X11 | macOS 15 ARM64 |
| --- | --- | --- |
| Pinned probe builds | Pass | Pass |
| Rust process-main-thread window | Render, resized render and loop return | Render observed; process exits on quit before loop return |
| Rust worker window | Pass | Rejected by main-thread guard |
| Dart JIT / AOT worker window | Both pass, callbacks and active Dart timer | Both rejected, application and runner report non-main OS thread |
| Input / IME | Untested in this run | Untested |
| Renderer scope | llvmpipe CPU Vulkan, Mesa 25.2.8, Xvfb, scale 1 | Apple virtual machine; renderer identity not established, scale 1 |

The initial runner classified the macOS Rust process's zero exit code as
successful. Inspection found no `run_return` or final `exit` event. The pinned
`gpui-pre-macos` `platform.rs:557` schedules `NSApplication terminate:` on quit.
This is a lifecycle constraint, not evidence that the FFI call returned. The
revised probe requires a checkpoint proving resize before quit and keeps loop
return separate. macOS resized rendering is unverified in the initial capture.

The current Dart-hosted dedicated-isolate arrangement is therefore unsuitable
for this macOS backend. Moving the Dart application to a different isolate does
not make its FFI call run on the OS main thread. No production port is selected.
The next isolated candidate is a native companion executable whose main thread
owns AppKit, with Dart retaining its application process and SDK. Its process
transport, bounded cleanup, JIT/AOT and actual reload must be proven before
adoption. A same-process Dart VM embedder remains an alternative requiring its
own bootstrap/runtime-distribution proof and a returning GPUI shutdown path.

The parallel Windows job [36181630592](https://github.com/AmeinEskinder/gpuidart/actions/runs/36181630592)
failed analysis on a relative import introduced by the final probe DPI change.
The earlier analysis result preceded that import; the 12 native and 27 Dart
behavioral results remain valid. The import is corrected to `package:` and
analysis is rerun before the next commit. The failure metadata is retained in
`reports/ci/run-36181630592.json`.

## Input and shutdown checkpoints, source `8afcece`

[Run 36182706923](https://github.com/AmeinEskinder/gpuidart/actions/runs/36182706923)
confirmed exact synthetic input text and one button click in all four Linux
launch variants. Each also rendered at 720 by 420, returned from the native
loop and exited normally. The software renderer and display scope are unchanged.
The macOS native executable also recorded the resized viewport and pre-quit
checkpoint, then terminated its process. Worker launch rejection is unchanged.
See [Linux records](hosted-input/linux/results.json) and
[macOS records](hosted-input/macos/results.json).

Windows hosted checks recovered in [36182707028](https://github.com/AmeinEskinder/gpuidart/actions/runs/36182707028).
The corrected import passed analysis, 12 native tests and 22 headless Dart tests.

## Companion candidate

`companion.dart` starts the native probe executable with `--stdio`. The child's
process main thread owns GPUI. A bounded 64-command channel carries the probe's
small label/close commands from its stdin reader to the UI loop; EOF requests
quit. The parent Dart process receives native records, keeps its timer running,
registers the existing development extension names, and waits for child exit.
This is an isolated transport feasibility test, not a production protocol or
Dart embedding implementation. It does not change the SDK's JSON protocol.

The candidate passed on Windows in JIT and AOT, including actual source reload,
invalid-source rejection and recovery through `DevSession`. The native PID,
input entity and synthetic input text were retained across the method change.
See [Windows candidate results](companion-windows/results.json) and
[reload evidence](companion-windows/reload.json). These results are pre-commit
checks based on `8afcece`; macOS/Linux candidate runs are still pending.

The next hosted runner treats macOS's rejected worker calls as explicit negative
capability checks. Only successful native-main and companion JIT/AOT/reload
checks can satisfy the macOS job. No rejected worker call counts as UI support.
