# Cross-platform acceptance status

This tracks the [work order](../../docs/cross-platform.md). It is an experimental
implementation with automated host acceptance, not a stable-release declaration.
The public Dart API, native ABI 1 and snapshot/dataset format are unchanged.
The GPUI Kit dependency pin is unchanged.

Latest verified implementation: **`7690c74`**. Windows
[36193687122](https://github.com/AmeinEskinder/gpuidart/actions/runs/36193687122),
macOS [36193687196](https://github.com/AmeinEskinder/gpuidart/actions/runs/36193687196),
Linux [36193687198](https://github.com/AmeinEskinder/gpuidart/actions/runs/36193687198)
and Unix packaging [36193689853](https://github.com/AmeinEskinder/gpuidart/actions/runs/36193689853)
all passed. Subsequent evidence-only commits do not change runtime code.

| Work-order area | Implementation / automated result | Remaining acceptance |
| --- | --- | --- |
| Backend and launcher feasibility | Proven on declared hosted targets; pin unchanged | Other hardware/backends unverified |
| Host lifecycle and clocks | Full applicable contracts, JIT/AOT and actual reload passed | Physical presentation not measured |
| Display/input integration | Native backends used; X11 geometry/resize verified at 1 and 1.25 | Human IME, Retina and physical/mixed-monitor checks |
| Build/check/package/CI | Implemented; both extracted packages passed; fresh Ubuntu container passed | Clean Mac and desktop/VM launches; distribution signing |
| Startup/memory baseline | Three JIT/AOT repetitions per host retained with stage/metric definitions | First useful display and presentation unmeasured |

The remaining acceptance items require desktop access or owner decisions. The
complete work order is therefore still open; automated passes do not close it.

## Declared targets

| Target | Launch strategy | Verified environment |
| --- | --- | --- |
| Windows x64 | Blocking native runner isolate | Windows 11 desktop; Windows Server 2022 headless CI |
| macOS 15 ARM64 | Dart-owned companion; GPUI on its process main thread; lifecycle extension 2 | GitHub runner, Apple Paravirtual Metal, scale 1 |
| Ubuntu 24.04 x64, glibc 2.39, X11 | Blocking native runner isolate | GitHub runner, Xvfb/Openbox, Mesa software Vulkan, scale 1 |

Native Wayland, Intel Macs, older macOS and other Linux distributions are
unverified. macOS uses separate application/UI processes; its extra transport
and memory costs need separate measurements.

## Completed host checks

Source `6467d6c` passed Windows, macOS and Linux SDK workflows. See
[host implementation and retained failures](host-implementation.md),
[raw Unix records](sdk-6467d6c/) and [Windows CI](../ci/README.md).

| Check | macOS | Linux X11 | Windows |
| --- | --- | --- | --- |
| Native tests | 17 passed | 17 passed | 12 passed |
| Headless Dart tests | 24 passed | 24 passed | 22 passed |
| Live-library/window Dart tests | 7 passed | 7 passed | 5 passed locally during host changes; excluded from hosted Windows CI |
| 100k JIT/AOT trace smoke | Passed | Passed | Earlier tracing milestone passed |
| Actual code reload, rejection and recovery | Passed | Passed | Local verification passed |
| Final trace, ownership and shutdown | Passed, includes companion | Passed | Passed |

The Unix additions cover owned process-group cleanup and companion startup
failure/reaping. A skipped or excluded suite does not count as a pass. Raw trace
smokes use debug native builds and are not performance comparisons. The stronger
explicit native-PID reload assertion passed at `f56bea1` on both Unix hosts:
[macOS](native-pid-reload-macos/reload.json) retained application PID 8612 and UI
PID 8617; [Linux](native-pid-reload-linux/reload.json) retained shared PID 5610.
Windows passed the assertion locally and its hosted headless workflow passed
at `f56bea1` as well. All three SDK workflows are green at that source.

## Packaging and baseline work

The portable tools build Linux archives and ad-hoc signed macOS `.app` bundles,
with compiled standalone verifiers, hashes, dependency inspection and runtime
image checks. [Packaging evidence](packaging.md) retains the first metadata-query
failure and the successful `f56bea1` follow-up: extracted AOT self-tests on both
targets, a fresh Ubuntu runtime-only container, and three JIT plus three AOT
startup/memory baselines per target. Clean Mac/desktop checks remain separate.
Source `7690c74` also passed the runtime-only macOS verifier with developer-tool
lookup disabled, both Unix package checks and the fresh Linux container again.
The [follow-up records](packages-7690c74/) retain these results separately.

X11 automated geometry checks passed at forced scales 1 and 1.25. At 1.25, the
960 by 720 logical viewport measured 1200 by 900 X11 client pixels; after resize,
800 by 600 logical measured 1000 by 750 physical. These are Xvfb checks, not
physical fractional-scaling or mixed-monitor verification.

## Gates that remain open

- Clean Windows and macOS launch without development SDKs. A clean Linux
  container is a narrower automated target; clean desktop/VM checks remain.
- Human IME composition, candidate placement/commit/cancel, selection,
  scrolling and window resizing on every declared OS/backend.
- Retina, physical Linux fractional scaling and mixed-monitor movement. Hosted
  macOS checks cover scale 1; Linux additionally has forced-scale 1.25 geometry
  and resize checks.
- Owner license selection and macOS public-distribution signing/notarization.
- The original Windows [reload observation](../mvp/attempt-023eef4/README.md).
  Passing later regressions does not localize that historical observation.
- First useful display and input-to-present latency. Draw acknowledgements and
  clock-correlated publication traces do not establish presentation timing.

Use the [Unix observation sheet](../../docs/unix-release-checks.md) and
[Windows release checks](../../docs/windows-release-checks.md) to retain actual
results. Automated Unicode/synthetic input must not be recorded as human IME.
