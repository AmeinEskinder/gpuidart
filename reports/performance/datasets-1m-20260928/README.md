# One million records through sliced uploads (2026-09-28)

The dataset row cap moved from 100,000 to 1,000,000, and records beyond about
4 MiB of encoded text now travel as a schema followed by appended slices
(`append` on the wire) behind `open`, `registerDataset` and `replaceDataset`.
This directory measures what that costs at 100,000 and 1,000,000 records.

## Method

[measure_large_dataset.dart](../../../tool/performance/measure_large_dataset.dart)
builds ROWS records of three columns (`ID`, `Instrument N`, a price) with
record IDs, opens a table over them with the window first (`deferDatasets`),
publishes a descending sort on the price column, and reads process memory
(Dart RSS and the native process counters) at start, after the records exist
in Dart, after the upload and after the sort. It ran as an AOT executable
against `target/release/gpuidart.dll` built from this tree on the Windows
machine in `reports/environment.json`; [aot-100000.json](aot-100000.json)
and [aot-1000000.json](aot-1000000.json) are the full outputs, and
[jit-1000000.json](jit-1000000.json) is an earlier `dart run` capture kept for
reference only, since the JIT runtime inflates the Dart-side memory.

## Results (AOT, release library)

| Rows | Slices | Build records in Dart | Open (window, schema, all slices) | Sort publish to inspect | Data bytes sent |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100,000 | 2 | 103 ms | 434 ms | 15 ms | 4.7 MB |
| 1,000,000 | 13 | 1,452 ms | 3,085 ms | 108 ms | 50.6 MB |

Per slice at 1,000,000 rows (medians over 13): Dart encode 52 ms, native parse
64 ms, native apply 79 ms (p99 296 ms, the last slices recompute the largest
view), submit to acknowledgement 200 ms. The sort recomputes the view over
1,000,000 records in 105 ms of native snapshot application.

Process memory, MiB (working set / private commit):

| Point | 100,000 rows | 1,000,000 rows |
| --- | ---: | ---: |
| Process start | 15.8 / 8.5 | 15.8 / 8.5 |
| Records built in Dart | 61.2 / 55.2 | 361.0 / 356.8 |
| After upload (native copy and window) | 176.7 / 187.9 | 614.4 / 650.7 |
| After sort | 177.9 / 189.6 | 613.0 / 648.9 |

At 1,000,000 rows the Dart records take about 345 MiB and the native copy
with the window about 250 MiB more; the sort's view index adds nothing
visible. The cap is a memory bound: an application that keeps the Dart copy
pays for a million records twice, once in Dart and once natively; the next
section releases the Dart copy.

## Without the Dart copy

`TableDataset(..., retainRecords: false)` releases the Dart records once
native holds them. The tool's `release` mode measures it, with a settle step
that churns short-lived allocation so the VM runs a major collection before
the reading; [aot-1000000-retain.json](aot-1000000-retain.json) and
[aot-1000000-release.json](aot-1000000-release.json) are the two runs, taken
minutes apart with the same library.

| Point, 1,000,000 rows | Retained, RSS MiB | Released, RSS MiB |
| --- | ---: | ---: |
| Records built in Dart | 361 | 360 |
| After upload, before the collector runs | 632 | 632 |
| After the settle step | 619 | 387 |
| After sort | 620 | 388 |
| Private commit after settle | 662 | 430 |

Releasing the copy returns about 230 MiB of the process at a million records
once the collector has run; until then the pages stay with the VM. The
upload itself is unchanged (13 slices, open 2.0 and 1.9 s, sort 73 and
78 ms), and the records stay editable by index with native validating record
IDs.

## Limits

One process, one run per size, one machine; no comparison with another
framework and no presentation measurement. `open` includes the 3.5 s of
slices at 1,000,000 rows because the fixture awaits them; an application
that needs the window sooner already has it after the first frame, before
the slices arrive. The 4 MiB slice estimate counts UTF-16 units and can be
tripled by escapes or non-ASCII text, still under the 16 MiB message limit.
