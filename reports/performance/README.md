# Measured performance milestone

Roadmap steps 5–6, scoped by [the work order](../../docs/performance-milestone.md).
Windows, macOS and Linux have separate machine-specific evidence; hosted results
do not rank operating systems or isolate language-runtime overhead.

| Deliverable | Evidence / outcome |
| --- | --- |
| Startup stages and data-size memory slopes | [Release baselines](baselines/README.md): empty/1k/10k/100k, JIT/AOT, library/data controls, normal and allocation-profile builds |
| macOS companion costs | [Separate process and transport analysis](baselines/macos-companion.md), with no invented same-process counterfactual |
| Snapshot-heavy gate | [18 runs / 720 replacements](snapshot-gate/README.md) demonstrate description-size costs |
| Three-strategy comparison | [162 normal + 54 profile runs](strategies/README.md), [stage/memory tables](strategies/results.md); patches and subviews remain experimental |
| Measured optimization | [Keep direct UTF-8 encoding](encoding/host-results.md), supported by byte checks, encoding-only results and actual-host comparisons |

The optimization changes encoding implementation, not the JSON wire format or
snapshot/dataset architecture. It adds about 41 KiB to the measured Windows
Watchlist executable. Repeated-encoding memory results are mixed; actual 100k
host memory falls in the recorded comparison. These qualifications remain in
the evidence rather than being turned into a universal memory claim.

All attempted workloads, failed builds, harness fixes and partial runs are
retained in their respective reports. CPU scene construction is the last
measured draw boundary. Presentation latency, physical Mac observations,
signing credentials and the historical reload disposition remain outside this
milestone. No new widget kinds were added.

Implementation `2fb9ef8` passed Windows/macOS/Linux SDK and Unix lifecycle CI.
Every evidence commit runs the same checks; see the
[commit-specific CI record](https://github.com/AmeinEskinder/gpuidart/actions?query=branch%3Amain).
