# Foreground pilot measurements, 2026-09-25

Four foreground runs completed. The repeated Rust/Dart comparison and the four-implementation comparison remain incomplete. These samples establish observations on this machine, not a performance ranking.

Production runtime code, dependencies, compiled application binaries and the snapshot/dataset architecture are unchanged. The benchmark driver and reporting scripts changed during this session. The successful application samples below all precede the driver timer change.

## Process observations

CPU covers the workload interval after warmup, with one logical core equal to 100%. Memory is the median of process samples taken every 250 ms. Each row is one process launch. These are not medians across repeated runs.

| Implementation | Workload seconds | Injected inputs | Skipped driver deadlines | CPU % of one core | Working set MiB | Private bytes MiB | Launch to HWND ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Rust | Idle, 10 | 0 | 0 | 0.94 | 85.21 | 97.52 | 244.88 |
| Dart AOT | Idle, 10 | 0 | 0 | 1.25 | 140.55 | 163.55 | 430.76 |
| Rust | Scroll, 10 | 599 | 1 | 23.90 | 97.22 | 106.56 | 316.48 |
| Rust | Cell, 2 | 10 | 0 | 1.55 | 85.93 | 98.07 | 284.75 |

Rust and Dart use the same GPUI Kit table, viewport and 100,000 records. Both idle windows reported DPI 120. There is only one idle sample per implementation, and other desktop activity was not controlled. The CPU difference is too weakly sampled to support an integration-overhead estimate. HWND discovery precedes showing the window and does not measure a usable or displayed first frame.

The scroll sample delivered 59.90 wheel events per second. Its skipped deadline excludes it from a matched-cadence ranking. Every delivered update in the successful cell sample was verified. The two-second cell preflight is not part of the requested ten-second repeated comparison.

Exact values and sample identifiers are in [foreground-pilots.json](foreground-pilots.json). Full process samples, timestamps, executable hashes, screenshots and application reports are in [foreground-preflight-20260925](foreground-preflight-20260925) and [paired-20260925-0](paired-20260925-0). The [measurement environment](measurement-environment.json) records the CPU, graphics drivers, display mode, power plan and source revision. The machine used the Balanced power plan and a 1920 by 1200 display reported by WMI as 59 Hz. The rendering adapter and exact fractional refresh rate were not established.

## Native drawing and publication

The Rust scroll process recorded 566 native draw samples, with p95 **3.873 ms** and p99 **4.305 ms**. That histogram is cumulative from window creation and includes startup and warmup. It is not a histogram restricted to the ten-second workload, a display-frame interval distribution, or input-to-present latency. Its sample count cannot establish missed display frames.

Each idle process recorded only three native draws over its entire lifetime. Their high percentiles mostly describe startup, so they are not used to compare steady-state drawing. The analyzer retains these raw histograms with their scope.

There is no completed foreground Dart edit workload in this session, so there are no new foreground publication-stage results to compare. Earlier publication measurements retain their original boundaries. Dataset publish-to-applied starts before encoding and ends when Dart receives the applied acknowledgement. Encoding, native parsing and native application are stages within that path; their percentiles must not be added together.

ETW capture was not requested because the prior access-denied restriction remains unresolved. Presentation intervals, missed display deadlines and input-to-response-present latency remain unmeasured. Native input-to-frame diagnostics also lack correlation to the frame containing a particular changed cell.

## Rejected attempts and driver findings

- An initial Rust scroll attempt lost foreground focus to another application. A subsequent attempt completed and supplied the scroll sample above.
- The ten-second Rust cell attempt injected 50 clicks but reported 49 updates. It was rejected. Its [failure record](paired-20260925-0/rust-cell/failure.json) and application report are retained. The cause of the missing update has not been established.
- A later Rust cell preflight stopped before input because Chrome owned the foreground. See [failure.json](driver-preflight-20260925/rust-cell/failure.json). No process measurements from that attempt are accepted.

The input timestamps exposed a separate driver problem. A requested one-millisecond PowerShell sleep waited 15.47 ms on average in a 100-sample local probe. A high resolution waitable timer averaged 1.46 ms, with a 1.99 ms maximum in that probe. Raw observations are in [driver-wait-probe.json](driver-wait-probe.json). Windows does not guarantee that a `timeBeginPeriod` request will supply the requested resolution in every process visibility state; [Microsoft documents that limitation](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod).

The driver now uses that waitable timer and places the pointer over the target before measuring clicks. Deadline accounting, focus checks and exact update-count checks remain active. The missing-click cause is still unresolved, and a foreground workload with the revised driver has not completed. The wait microprobe alone does not verify input delivery. All new failures save an explicit exclusion record and any recorded input schedule.

## Resume measurement

An uninterrupted foreground desktop is still needed. Start with cell, burst and scroll preflights using the revised driver, then use a fresh run ID for three alternating Rust/Dart repetitions. Run all four implementations in four rotated repetitions afterward. Commands are in the [benchmark guide](../../benchmarks/README.md#capture-foreground-measurements).

Keep the comparisons separate. Rust versus Dart estimates integration cost with the same native table. Shell and GPUIX use different list and update implementations, so their results compare complete implementations. Presentation measurements require both ETW access and changed-cell frame correlation.

The [production DPI requirement](../../docs/integration.md#windows-production-dpi-requirement) is now recorded. Production packaging still needs equivalent DPI configuration and verification of the actual shipped executable.
