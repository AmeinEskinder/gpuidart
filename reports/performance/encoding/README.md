# Direct JSON-to-UTF-8 candidate

The startup baseline attributes about 24.74 ms to JSON and 5.88 ms to UTF-8 in
the Windows AOT 100k fixture. This identifies a concrete candidate: use Dart's
`JsonUtf8Encoder` to avoid building the intermediate JSON string. The candidate
now uses that encoder in the host, with an internal compile-time legacy control
for equivalent before/after capture. **Decision: keep**, based on the
[actual-host comparison](host-results.md). There is no wire-format or ABI change.

`capture_encoding.dart` compares the existing two-stage encoder with the fused
encoder in fresh JIT/AOT processes. Fixtures cover an incremental cell message,
a 2,048-property snapshot, the initial 100k dataset shape and a Unicode-heavy
100k payload. The first encode is separate from 25 subsequent encodes. Three
repetitions rotate fixtures, encoder order and execution mode. Timing covers
encoding only; RSS/high-water marks include the fixture/runtime and natural GC.
Every result hash must agree across encoder, mode and repetition. There is no
renderer, FFI or presentation claim in this microbenchmark.

A separate byte-equivalence check includes control characters, Japanese, emoji,
sampled UTF-16 code units, unpaired surrogates, nesting and numeric edge values.
Both encoders must reject cycles, invalid map keys and nonfinite numbers. The
local check passed. Analyzer escape/brace findings and the corrected run are
retained in `implementation/`.

## Encoding-only measurements

Source `cbe8595`, [hosted run 36253927656](https://github.com/AmeinEskinder/gpuidart/actions/runs/36253927656).
All 48 fresh-process cases per platform passed, and output hashes agree. Raw
captures and summaries are in `micro-{windows,linux,macos}/`. AOT medians of the
first encode across three runs, milliseconds (legacy → fused):

| Fixture | Windows x64 | Linux x64 | macOS ARM64 |
| --- | ---: | ---: | ---: |
| 2,048-property snapshot | 4.758 → 3.476 | 5.878 → 4.445 | 3.597 → 2.540 |
| 100k initial dataset | 39.097 → 23.649 | 40.213 → 25.734 | 28.957 → 16.211 |
| 100k Unicode records | 89.350 → 43.538 | 105.017 → 48.250 | 62.932 → 24.647 |

Subsequent median encodes also improve for these cases; tiny cell messages are
at microsecond timer granularity. JIT results remain separate in the summaries.
These are encoding costs, not complete startup or interaction times.

Memory is mixed. After 26 ASCII initial encodes, median peak RSS is about 6 MiB
higher with fusion on Windows and 5.3 MiB higher on macOS. Snapshot peaks fall
by about 15.9 / 14.6 MiB, respectively. Linux peak RSS is already about 120 MiB
before encoding and often does not advance, so it cannot resolve candidate
allocation differences here. No GC is forced, and process peaks do not isolate
temporary buffers. This is why the actual-host comparison is required before
the decision; avoiding an intermediate string does not prove lower peak RSS.
