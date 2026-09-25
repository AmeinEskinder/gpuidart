# Portable packaging and baseline checks

`tool/build.dart`, `tool/package.dart` and `tool/verify_package.dart` provide one
Dart command family. Windows delegates to its existing PowerShell implementation.
Unix packages use release-native builds and Dart AOT, record source/file hashes,
and include a compiled standalone verifier. macOS uses an ad-hoc signed `.app`;
Linux uses an archive with documented system runtime prerequisites.

The verifier extracts outside the repository, runs from an unrelated directory
with a fresh home and restricted environment, inspects dependencies with `otool`
or `ldd`, and checks the libraries reported by both running application and UI
processes. It records native dimensions/scale and macOS main-thread ownership.
Temporary packages and reports are retained. A failed attempt writes `passed:
false`; a successful old report cannot remain as the current result.

The manually dispatched `Unix release packages` workflow builds both declared
targets, verifies extraction, records three JIT and three AOT baseline runs in
alternating order, and tests the Linux artifact in a fresh runtime-only Ubuntu
container. Artifacts and logs are retained separately. Human input, physical
scaling, clean desktop/VM launch and macOS Developer ID/notarization remain
separate gates. See [the observation sheets](../../docs/unix-release-checks.md).

## Baseline boundaries

The driver and application use the verified shared OS clock. The record includes
driver launch, Dart `main`, record construction, host readiness, and the
acknowledgement of an explicitly requested draw. The last interval is not first
useful display or presentation. Native traces preserve process IDs and separate
publication stages. Instrumentation is enabled throughout these smoke baselines.

Memory and CPU snapshots are keyed by PID, so Linux's shared application/UI
process is counted once. macOS reports application and companion separately.
Linux RSS and PSS come from
[`smaps_rollup`](https://docs.kernel.org/filesystems/proc.html); macOS resident
size and physical footprint come from `proc_pid_rusage`. RSS totals are not
unique allocated memory. These metrics are not renamed as Windows private bytes.
CPU is cumulative user/system time from `getrusage`, sampled around a two-second
idle period; diagnostic work contributes to the interval. Three repetitions on
different hosted machines cannot establish a cross-platform performance winner.

## Initial implementation verification

Dart analysis passes. The standalone verifier compiles to AOT on the available
Windows development host, and the portable build command successfully delegates
to the existing Windows build. This establishes tooling compilation/delegation
only. Unix package execution, signing checks, loaded-library closure and the
baseline runs remain pending the first release-package workflow.

## First hosted package attempt

Source `6467d6c`, [run 36191300257](https://github.com/AmeinEskinder/gpuidart/actions/runs/36191300257),
built both release-native targets and compiled both Dart applications/verifiers.
macOS ad-hoc signing and strict signature verification also succeeded. Both
jobs then failed when offline `cargo metadata` requested dependencies belonging
to the other operating system. Package verification and baselines were skipped.
The [failure log](package-metadata-failure.log) and run metadata are retained.

The metadata query now specifies the package's Rust target with
`--filter-platform`. This preserves offline, locked dependency resolution and
limits the inventory to that target. Extraction/runtime verification still
requires a successful follow-up job.

## Verified evaluation packages at `f56bea1`

[Run 36192771602](https://github.com/AmeinEskinder/gpuidart/actions/runs/36192771602)
passed on both targets. [Raw records](packages-f56bea1/) include environment
enumeration, file/source hashes, static dependencies, actual loaded images,
native scale/geometry, three JIT and three AOT baseline runs per target, and the
Linux runtime-only container's package inventory and image identity.

| Artifact | Archive bytes | Installed payload bytes | Extracted launch |
| --- | ---: | ---: | --- |
| macOS 15 ARM64 | 13,526,086 | 37,059,100 | Passed; separate UI PID on main thread, strict ad-hoc signature check |
| Ubuntu 24.04 x64/X11 | 23,635,153 | 72,261,874 | Passed on hosted image and fresh runtime-only container |

Installed sizes include the verifier, manifest and documentation; system
runtime prerequisites are excluded. Archives were downloaded and their hashes
matched the verification records. They are local evaluation artifacts under
`build/unix-evaluation-packages/`, not a public release. Their SHA-256 values are:

- macOS: `c5cc5bf993bd98607dc4a08c01bef204809300c249dadf674a3419d3e0fdfc5a`
- Linux: `f804fbcec3e4f71bbb5321051a34ae01169c3696f942ba1ac762aa16b3131d97`

The Linux container contains no Dart, Rust or Cargo executable. Its self-test
loaded only the packaged SDK library and documented system libraries. This
establishes runtime closure for that Ubuntu container, using software Vulkan;
it does not establish a physical desktop or another distribution. The macOS
runner still contains developer tools. Both checks ran at scale 1. macOS
reported a 960 by 653 logical viewport on its small virtual display; Linux
reported 960 by 720. Neither result proves Retina/fractional scaling.

### Startup and memory baseline

The fixture constructs 100,000 two-column records, opens the same view, requests
two repaints and samples memory after two idle seconds. Native code is a release
build; tracing is enabled. Values below are medians of three runs, with the
observed min–max in parentheses. Startup columns are cumulative milliseconds
from the driver's launch timestamp; do not add their medians together.

| Host / mode | Dart main | Records constructed | Host ready | Requested draw acknowledged |
| --- | ---: | ---: | ---: | ---: |
| macOS JIT | 673.4 (526.7–815.9) | 715.9 (567.7–860.7) | 1,097.0 (862.4–2,064.2) | 1,225.8 (1,004.3–2,220.3) |
| macOS AOT | 30.4 (29.7–53.2) | 57.3 (50.4–79.6) | 362.0 (359.8–442.3) | 507.8 (504.7–583.2) |
| Linux JIT | 492.2 (492.0–497.0) | 546.3 (541.3–549.9) | 804.0 (800.8–809.2) | 886.6 (885.2–1,260.7) |
| Linux AOT | 7.4 (7.4–7.9) | 35.6 (34.8–36.0) | 231.2 (228.7–231.7) | 328.2 (325.6–329.7) |

The launch interval includes the owned-session helper and, for JIT, the Dart
command's startup. It does not isolate VM boot. Host readiness is not first
useful display; requested-draw acknowledgement is not presentation. First-run
effects remain in these samples. The Mac VM and Linux software renderer are
different environments, so these numbers do not rank platform performance.

Memory below is MiB after the idle interval. Linux application/UI share one PID
and are listed once. The macOS processes are separate; resident sizes may include
shared pages and are not summed as unique memory.

| Host / mode / process | Resident size or RSS | Physical footprint (Mac) / PSS (Linux) |
| --- | ---: | ---: |
| macOS JIT application | 248.33 (248.16–250.77) | 177.67 (177.47–180.69) |
| macOS JIT UI | 71.27 (70.56–71.50) | 48.31 (48.02–48.39) |
| macOS AOT application | 71.91 (71.91–71.98) | 40.66 (40.66–40.72) |
| macOS AOT UI | 71.25 (71.17–71.38) | 48.71 (48.03–48.72) |
| Linux JIT shared process | 404.42 (404.37–417.95) | 353.03 (352.67–366.27) |
| Linux AOT shared process | 233.92 (233.31–234.23) | 211.52 (211.02–211.79) |

Each raw baseline records the metric source, per-process counters and loaded
images. The table uses `after_idle.by_pid` and deduplicates PID roles. These
are initial instrumentation baselines, with different OS memory definitions,
not evidence about Dart versus other language runtimes.

### Standalone verifier without developer tools

The first macOS package verifier calls `otool`. That tool comes from the Apple
developer toolchain, so it is unsuitable as a prerequisite for a clean Mac.
The next package revision retains build-time dependency inspection in the
manifest and adds explicit `--runtime-only` verification. That mode still
checks file hashes, signatures, actual loaded images and application behavior;
it labels static inspection as recorded at build time. Default mode reruns the
inspection tools. A hosted check with an invalid `DEVELOPER_DIR` is being added
to prove that this mode does not invoke `otool`. It is not a clean-Mac claim.

## Runtime-only and scale follow-up at `7690c74`

[Run 36193689853](https://github.com/AmeinEskinder/gpuidart/actions/runs/36193689853)
passed both package jobs. [Raw follow-up records](packages-7690c74/) retain the
new artifacts, repeated baselines and Linux container verification separately
from the first baseline series above.

The macOS runtime-only verifier passed while `xcrun --find otool` failed with an
invalid `DEVELOPER_DIR`. No machine-wide tool setting changed. Hashes, ad-hoc
signatures, actual library loading and the self-test still passed. Static
dependencies were explicitly labeled as inspected at build time. This closes
the verifier's dependency on developer tools in that mode, while a clean Mac
without installed tools remains a separate environment check.

The X11 display probe passed at 100% and 125%, including OS-requested resizing.
It compares the native logical viewport against `xdotool` client geometry.
At 125%, 960×720 logical became 1200×900 physical, then 800×600 became 1000×750.
The scale came from the pinned backend's `GPUI_X11_SCALE_FACTOR` override under
Xvfb; it does not establish physical monitor or compositor scaling behavior.

| Current evaluation artifact | Archive bytes | Installed payload bytes | SHA-256 |
| --- | ---: | ---: | --- |
| macOS ARM64 | 13,530,171 | 37,081,380 | `570f9394406840a64a8149bdb03005ab4a4532a42b3169e844196b11491e1a7b` |
| Linux x64 | 23,637,345 | 72,282,256 | `d8ae256197dc61c96692d7fb38dd42838959931e5ef450d186df3ae48d25b0a9` |

Downloaded artifacts in `build/unix-evaluation-packages-7690c74/` match these
hashes. Both manifests report clean source at `7690c74`. The size includes the
standalone verifier and documentation, and excludes system prerequisites.
