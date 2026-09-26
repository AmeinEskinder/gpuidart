# macOS companion-process costs

Measured at `e9c0c27` in the [successful hosted job](https://github.com/AmeinEskinder/gpuidart/actions/runs/36250180296/job/108426624601).
macOS 15.7.9, `VirtualMac2,1`, ARM64, 3 physical CPUs reported, 7 GiB memory,
paravirtual Metal. This is hosted measurement, not a physical Mac release check.
All 78 timing cases and 26 separate allocation-profile cases passed. Native/AOT
hashes and build flags are in `macos-e9c0c27/`.

## Per-process memory and startup

Normal release, AOT, median of three process repetitions. Settled memory within
each process is the median of three observations; no forced GC.

| Rows | Launch to first CPU content paint, ms | Application RSS / footprint, MiB | UI RSS / footprint, MiB |
| ---: | ---: | ---: | ---: |
| 0 | 318.23 | 20.81 / 7.88 | 52.91 / 32.75 |
| 1,000 | 294.16 | 21.55 / 8.55 | 55.13 / 34.58 |
| 10,000 | 328.34 | 26.69 / 12.55 | 56.44 / 35.55 |
| 100,000 | 358.85 | 72.52 / 41.11 | 71.83 / 49.14 |

The application and UI have different PIDs. RSS contains shared mappings; the
two RSS entries must not be called unique physical memory when added. Footprint
is a distinct Darwin accounting metric. The table's UI memory is not entirely
companion overhead: any native implementation still needs rendering/control state.

The application process grows by ~33.23 MiB of footprint from zero to 100k rows;
the UI process grows by ~16.39 MiB. These endpoint differences include the table's
fixed cost, publication buffers, allocation/GC behavior and retained records.
Intermediate sizes and every repetition remain available in the raw summaries.

## Matched application controls

Data-only builds the same authoritative Dart data and never loads GPUI. Library-only
adds the GPUI library/runtime probe but never starts a host or UI process.

| Control | Rows | Application RSS, MiB | Application footprint, MiB |
| --- | ---: | ---: | ---: |
| Data-only | 0 | 11.20 | Not collected without library load |
| Library-only | 0 | 19.34 | 7.06 |
| Host with companion | 0 | 20.81 | 7.88 |
| Library-only | 100,000 | 43.59 | 31.31 |
| Host with companion | 100,000 | 72.52 | 41.11 |

At 100k, the host application role has ~9.80 MiB more settled footprint than the
library-only control. That is an observed difference after encoding, native
staging, socket setup and callbacks; it cannot be assigned solely to the socket,
VM or raw JSON. It is separate from the UI-process footprint.

## Initial transport

Normal AOT medians at 100k:

| Stage | ms | Boundary |
| --- | ---: | --- |
| Dart encode/copy | 34.40 | JSON, UTF-8 and FFI buffer |
| Application native initial decode | 11.81 | First native parse in the Dart process |
| Dart companion start | 2.75 | Socket setup and `Process.start`; child readiness is later |
| Application native companion encode | 2.79 | Re-serialize parsed initial state into a transport frame |
| Application native socket write | 5.05 | Framed write/flush; may overlap child receive |
| UI companion decode | 10.60 | Parse initial frame in the UI process |
| UI window creation | 67.10 | GPUI `open_window`, which can include painting |

The frame body is 2,178,177 bytes. The extra re-encode and child decode are concrete
costs of this companion implementation. The write interval is not a pure transport
latency measurement. Child receive includes waiting for the sender, and launch,
initialization and first paint overlap other spans. Do not add all stage medians.

The median of per-run median `inspect` round trips is ~166 us at 100k and ~231 us
at zero rows. These are diagnostic requests with different reply sizes, process
scheduling and serialization. They do not isolate socket cost, establish a data-size
speedup or measure input-to-present latency. Twenty requests per run and three
runs are descriptive evidence only.

## Temporary Rust allocations

One separate release allocation-profile repetition, AOT:

| Rows / role | Live requested bytes | Lifetime peak requested bytes | Cumulative requested bytes |
| --- | ---: | ---: | ---: |
| 0 / application | 246,276 | 386,539 | 1,917,224 |
| 100k / application | 246,276 | 18,564,590 | 27,584,743 |
| 0 / UI | 7,264,085 | 7,423,915 | 9,648,925 |
| 100k / UI | 23,030,844 | 23,203,954 | 34,523,997 |

The application role's Rust live requested bytes return to the same sampled value
at zero and 100k, after a much larger high-water mark during startup. This supports
temporary native staging rather than a permanently retained extra native dataset
in that process. It does not imply those pages were returned to the OS. Counters
exclude Dart, external malloc, allocator overhead and GPU allocations, and their
concurrent reads are not an atomic heap census.

In normal 100k runs, application footprint peaks at ~56.64 MiB versus ~41.11 MiB
settled; UI footprint peaks at ~49.64 MiB versus ~49.14 MiB settled. The two
processes' lifetime peaks need not occur simultaneously. These are different
measurements from Rust requested allocation sizes and must not be subtracted
from those sizes to invent a Dart heap estimate.

## Conclusions and limits

The companion's two-stage native decode and intermediate serialization are now
quantified, as are the two processes and temporary native staging. The Linux
direct/companion control in the baseline README provides a same-machine launch-model
comparison on Linux. macOS has no supported shared-process control in this SDK;
this report does not claim its hypothetical net overhead. It also does not make
cross-platform speed, unique-memory or presentation claims. Architecture remains
unchanged pending measured optimization experiments.
