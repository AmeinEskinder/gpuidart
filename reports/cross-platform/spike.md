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
