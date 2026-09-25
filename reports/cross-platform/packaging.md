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
