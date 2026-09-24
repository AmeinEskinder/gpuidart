# Retained dataset publication

AOT executable and release Rust DLL, with 120 sequential awaited updates per phase after eight warmups. Cases use the same three-column table, view, viewport, values and update indices. Only record count changes. Timing ends at the native acknowledgement plus Dart state commit. Updates may coalesce into fewer rendered frames; this is not an input-to-present benchmark.

The runner asserts identical transferred bytes and native record work across 100, 10,000 and 100,000 records. Every cell phase checks the result in both Dart and Rust and confirms the existing table renders after updates.

| Records | Operation | Max bytes/update | Records checked/update | JSON encode p95 | Native apply p95 | Dart operation to applied p95 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | cell | 153 | 1 | 13 us | 5 us | 130 us |
| 100 | row | 163 | 1 | 12 us | 5 us | 117 us |
| 100 | batch10 | 621 | 10 | 32 us | 6 us | 166 us |
| 100 | counter | 433 | 0 | 26 us | 9 us | 197 us |
| 10000 | cell | 153 | 1 | 14 us | 5 us | 123 us |
| 10000 | row | 163 | 1 | 15 us | 5 us | 133 us |
| 10000 | batch10 | 621 | 10 | 43 us | 7 us | 228 us |
| 10000 | counter | 433 | 0 | 20 us | 7 us | 134 us |
| 100000 | cell | 153 | 1 | 16 us | 5 us | 195 us |
| 100000 | row | 163 | 1 | 14 us | 5 us | 147 us |
| 100000 | batch10 | 621 | 10 | 32 us | 6 us | 196 us |
| 100000 | counter | 433 | 0 | 20 us | 6 us | 138 us |

A cell edit sends one value. A row edit sends three values. `batch10` edits one cell in each of ten rows. A counter update sends a whole view snapshot with a dataset reference and **zero dataset bytes**. The raw report includes p50/p95/p99, native parsing, descriptions, initial upload size and process memory. Native parse/apply durations are integer microseconds, so zero means less than one microsecond.

Initial upload and explicit replacement still cost O(total records). Ordinary view descriptions, cell edits and row edits do not include or scan the full dataset. Table storage remains O(total records) in both Dart and Rust. The snapshot protocol no longer accepts inline records. Rust's table data type does not implement Clone or PartialEq.

Native allocation verification is in [data-allocations.json](data-allocations.json). It measures Rust JSON decode and transaction application separately from rendering and callbacks. Compare its identical allocation counts across dataset sizes, not its different fixture's byte count with the live application above.

The previous full-data snapshot measurements are preserved in [baseline-snapshots/summary.md](baseline-snapshots/summary.md). They are a historical local sample, not a matched input-latency comparison. Percentiles for different intervals have not been added.

Reproduce with `./tool/package.ps1` followed by `dart run tool/measure_data.dart`. See [../docs/datasets.md](../docs/datasets.md) for the API and transaction contract.
