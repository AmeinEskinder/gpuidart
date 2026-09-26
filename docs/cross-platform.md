# Cross-platform work order: macOS and Linux hosts

This is a development work order, not evidence that any platform support exists or has been measured. The Windows host remains the reference implementation and must stay green throughout. The snapshot/dataset wire protocol is OS-agnostic and does not change. Source: `e8a176a`.

Implementation progress and per-target acceptance are tracked separately in
[cross-platform status](../reports/cross-platform/status.md). The inventory below
describes the starting revision.

## Objective

Run the existing Dart API and snapshot/dataset protocol on macOS and Linux. Extend packaging, tooling and CI with equivalent behavioral verification for each declared target. Keep one public SDK. Record supported OS versions, CPU architectures and Linux display backends explicitly; success on one target does not establish support for every variant.

## What is OS-specific today (inventory)

| Component | Windows dependency | Location |
| --- | --- | --- |
| Host gate | `Platform.isWindows` throw | `lib/src/host.dart` |
| Tracing | Windows-only Dart gate and `kernel32` QPC/thread-ID calls in both languages; the Rust link is unconditional | `lib/src/tracing.dart`, `native/src/trace.rs` |
| Launch model | Dedicated `gpui-native-loop` isolate blocks in `gd_run`; GPUI app runs on that isolate's thread | `lib/src/host.dart`, `native/src/lib.rs` |
| Library loading | `.dll` lookup and fallback paths | `lib/src/host.dart` |
| DPI | Embedded manifest, PerMonitorV2 checks | package verifier, `lib/src/windows.dart` |
| Dev-session teardown | Windows uses `taskkill /T /F`; the existing Unix fallback kills only the tracked process | `tool/src/dev_session.dart` |
| Benchmark input tracing | `#[link(name = "user32")]` | `benchmarks/native/src/input_trace.rs` |
| Toolchain | MSVC, Windows SDK, PowerShell scripts | `tool/*.ps1`, `benchmarks/*.ps1` |
| Packaging | CRT redistributable, ZIP layout | `tool/package.ps1`, `tool/windows/` |
| Test eligibility and fixtures | Four Dart test files use `@TestOn('windows')`; DLL names, fixture compilation and the incompatible-library probe are platform-specific | `test/*_test.dart`, `tool/build_test_fixtures.ps1` |

## Phase 0: feasibility spike

Before committing to a port, establish on real hardware or runners:

1. Define the initial target matrix, including macOS architecture/minimum OS, Linux distribution and libc baseline, and X11/Wayland coverage. Record GPU, driver, compositor, scaling, toolchain versions and dependency pins using `reports/environment.json` as a starting point. Identify whether each environment can display a real GPU-rendered window.
2. Build and run the pinned toolkit's examples (`gpui-kit` @ `21622a70efd25219d26aa459164878c4da9e39f8`, `gpui-pre` 0.3.6) on each target. Verify a real window, input, resize and clean shutdown. Keep compile, headless, software-rendered and hardware-rendered results distinct. Localize failures to environment, dependency/backend or adapter before deciding to upgrade the pin or defer a target. A pin change requires renewed Windows acceptance and any affected performance baseline.
3. Prove GPUI thread ownership with native thread IDs and a platform main-thread check. AppKit view operations and event handling belong on the process main thread. Determine whether each Linux backend accepts the current blocking-runner arrangement. A Dart isolate name or entry point is not evidence of OS-thread identity.
4. Spike the Dart launch mechanism separately from the Rust-only example, in both JIT and AOT. On macOS, identify how the executable starts and keeps GPUI's event loop on the OS main thread while Dart application callbacks remain runnable. Check VM-service discovery, selection of the application isolate, close/error propagation and callback lifetime. A native bootstrap or Dart embedding may be necessary; do not assume that moving Dart code to a worker isolate supplies this mechanism.
5. Record commands, source revisions, failures and results in `reports/cross-platform/spike.md`. Mark each target as pass, fail or untested, and choose its launch strategy from that evidence. Isolated probe code is allowed; keep production host code unchanged in this phase.

The source review does not complete Phase 0. No macOS/Linux runtime evidence is recorded by this work order. [Apple's thread-safety guidance](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html) establishes the AppKit constraints. [Dart's VM documentation](https://github.com/dart-lang/sdk/blob/main/runtime/docs/README.md#how-does-dart-vm-run-your-code) explains that isolate-to-OS-thread mapping depends on embedding and scheduling; the chosen launcher still needs a runtime probe.

## Phase 1: host lifecycle

- Define a per-platform launch strategy behind one Dart entry point. Windows keeps the current dedicated-isolate arrangement.
- macOS: implement the launch strategy proven in Phase 0. A process-main-thread native loop with Dart application code elsewhere is a candidate arrangement, with bootstrap, runtime distribution and JIT/AOT implications. Integrate it with the existing `tool/src/dev_session.dart` contract and retain the application object through code reload.
- Linux: adopt the current arrangement only for backends where the spike proves it works. If it fails, investigate that backend's event-loop requirements and prove an alternative launch strategy before implementation.
- Replace the `Platform.isWindows` gate with per-platform capability checks that fail with actionable errors.
- Abstract native library loading and search locations, including `.dll`, `lib*.dylib`, `lib*.so` and packaged bundles. Retain the ABI-version handshake. Keeping the UI wire protocol stable does not require freezing a host lifecycle ABI that proves insufficient: use a versioned extension or explicit ABI bump if needed, with compatibility tests.
- Resolve the unconditional native clock link and Dart clock bindings as prerequisites for host compilation and trace tests. Both runtimes must use a demonstrated common monotonic clock domain, either through a native clock API or matching platform calls. Record units, frequency, origin, suspend behavior and ordering uncertainty per platform. Do not subtract unrelated clocks or copy QPC's one-tick uncertainty rule to other clocks. Retain request correlation, bounds and payload omission. Restrict `user32` input tracing to Windows when the benchmark feature is enabled.
- Preserve callback delivery, bounded queues, request/shutdown deadlines, the one-host guard and ownership until the native loop has actually returned. Verify failures during startup, reload and close, not only successful launch.
- Retain Windows process-tree teardown and implement bounded cleanup on macOS/Linux, including launcher children and startup failures.

Acceptance: equivalent lifecycle and live-window contracts pass on each targeted platform. Replace Windows-only test eligibility, fixture paths and probes as those targets become supported. Record executed and skipped test counts; a platform exclusion cannot count as a pass.

## Phase 2: display and input integration

- DPI: macOS Retina backing-scale handling and Linux fractional scaling replace the PerMonitorV2 machinery; the package verifier gains per-OS equivalents of the current DPI checks.
- Input/IME: IME behavior differs per platform. The existing human IME verification protocol (`docs/windows-release-checks.md`) needs macOS and Linux observation sheets; do not claim IME support from automated input injection.

## Phase 3: tooling and CI

- Port build/check/package flows so they run on each host OS. Prefer extending the existing Dart tooling (`tool/*.dart`) over triplicating PowerShell/bash; keep `tool/check.ps1` working on Windows.
- Extend hosted CI to the declared Windows/macOS/Linux targets with explicit runner OS images and architectures. Record the latest verified Windows source in [CI evidence](../reports/ci/README.md). Keep headless and real-window jobs distinct. If a runner excludes `live-window` suites, record them as untested and require a separate real-window result before claiming support. Preserve suite serialization for tests sharing process-global native state.
- Per-OS packaging verification: use the correct bundle/launcher and native loader search paths; extract outside the repository, use an unrelated working directory and restrict the environment. Use `otool -L` / `ldd` for dependency inspection, and separately record libraries actually loaded by the self-test process, such as dyld image paths or Linux process mappings. Define macOS signing/notarization requirements and Linux runtime-library prerequisites for the intended distribution channel.
- Exercise an extracted package without development SDKs on a clean environment per target. Hosted build images and restricted PATH tests alone do not establish this gate.

## Phase 4: verification gates per platform

For each platform, before claiming support:

1. The full applicable native and Dart behavioral suites pass. The current Windows reference has 12 native and 27 Dart tests. Port common contracts, add platform cases and justify exclusions explicitly; matching a total test count is insufficient.
2. Package verification and a clean-environment launch pass, including the self-test from an extracted bundle, dependency/runtime versions, artifact hashes and actual loaded-library paths.
3. The 100,000-row smoke workload passes, JIT and AOT, with trace capture.
4. Reload verification passes with the prepare/render ordering fixed in `edffde4`. Preserve invalid-source rejection, recovery, application/native identity and unchanged dataset publication checks.
5. Human input, IME composition, selection, scrolling and scaling checks pass on each declared backend, with retained observations. Automated character injection is insufficient.
6. Startup and memory baselines use defined workloads and stage boundaries. Existing traces cover publication and some host readiness, not external launch, VM boot, first useful display or presentation. Add missing measurements or mark them unmeasured. Record memory metric definitions separately for each OS; Windows private bytes/working set do not automatically map to Linux RSS/PSS or macOS footprint. Different hardware, drivers and runtime builds limit cross-platform attribution even with matching phases.

## Ordering and non-goals

- Open Windows release gates remain independent and ahead in priority: human IME verification and the unlocalized reload observation. [Clean Windows launch passed](../reports/release/README.md), and the owner selected the [MIT License](../LICENSE). Cross-platform work must not be used to defer remaining gates.
- Non-goals for this work order: mobile, web/WASM, multi-window, and snapshot/dataset protocol or styling changes. Those are separate decisions with their own gates.
- No per-platform API forks in `lib/gpuidart.dart`. Platform differences surface as capabilities and errors, not different method sets.
- Each phase lands behind evidence: a phase is complete when its acceptance items are recorded in `reports/cross-platform/`, not when code compiles.
