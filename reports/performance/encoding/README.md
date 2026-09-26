# Direct JSON-to-UTF-8 candidate

The startup baseline attributes about 24.74 ms to JSON and 5.88 ms to UTF-8 in
the Windows AOT 100k fixture. This identifies a concrete candidate: use Dart's
`JsonUtf8Encoder` to avoid building the intermediate JSON string. Production
encoding remains unchanged while the candidate is measured.

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
retained in `implementation/`. Hosted results and the keep/revert decision follow.
