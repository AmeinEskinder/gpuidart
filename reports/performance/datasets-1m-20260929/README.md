# One million records as packed slices with one recompute (2026-09-29)

The [previous measurement](../datasets-1m-20260928/README.md) uploaded a
million records as 13 JSON slices, each of which recomputed every view over
the dataset. This directory measures the record path after four changes:
the records of a slice travel as length-prefixed UTF-8 behind a JSON header
instead of as JSON text; native stores and acknowledges every slice but
recomputes views, tables and charts once, at the last one; native checks
record IDs against a sorted index of their hashes instead of rebuilding a set
of a million strings per slice; and Dart packs the next slice while native
applies the current one.

## Method

The same [measure_large_dataset.dart](../../../tool/performance/measure_large_dataset.dart)
as before, compiled ahead of time and run against `target/release/gpuidart.dll`
built from this tree on the machine in `reports/environment.json`: three runs
each with the Dart copy retained and released at 1,000,000 records and one at
100,000, alternating modes, minutes apart. The tool reports the time to build
the records in Dart, the open (window, schema and every slice), the sort
publish to its inspect, process memory at each point and the per-slice
metrics: Dart packing, native parse on the calling thread, native apply on
the UI thread and submit to acknowledgement. The machine was busier than on
the 28th: the pure Dart record build, the same work in both series, took 1.6
to 2.6 s against 1.45 s then, so each open is read beside its build.

## Results, 1,000,000 records (AOT, release library)

| Run | Build records in Dart | Open (window, schema, 13 slices) | Sort publish to inspect | View recomputes |
| --- | ---: | ---: | ---: | ---: |
| Retained 1 | 1,613 ms | 1,267 ms | 148 ms | 2 |
| Released 1 | 1,609 ms | 1,149 ms | 147 ms | 2 |
| Retained 2 | 1,957 ms | 1,582 ms | 117 ms | 2 |
| Released 2 | 2,110 ms | 1,858 ms | 159 ms | 2 |
| Retained 3 | 2,309 ms | 1,759 ms | 155 ms | 2 |
| Released 3 | 2,611 ms | 1,631 ms | 144 ms | 2 |
| 28th, retained | 1,452 ms | 3,085 ms | 108 ms | 13 |

Per slice, medians over the 13 slices, with the range across the six runs:

| Stage | 28th (JSON, recompute per slice) | This series (packed, one recompute) |
| --- | ---: | ---: |
| Dart encode or pack | 52 ms | 24 to 34 ms, overlapped with the previous apply |
| Native parse (calling thread) | 64 ms | 33 to 60 ms |
| Native apply (UI thread) | 79 ms, p99 296 ms | 12 to 20 ms, p99 32 to 41 ms |
| Submit to acknowledgement | 200 ms | 68 to 110 ms |

Bytes sent rose from 50.6 MB of JSON to 52.6 MB of packed cells, since the
length prefixes cost more than the quotes they replace on these short cells;
the saving is the quoting and unquoting, not the bytes. The two runs whose
record build was closest to the 28th's opened in 1.15 and 1.27 s; the median
over all six is 1.61 s, and the slowest, on the busiest moment, 1.86 s. The
acceptance for this move was an open under 1.5 s with a single recompute:
the recompute count is 2 in every run (the deferred schema counts one, the
last slice one), and the open meets 1.5 s when the machine is as quiet as it
was on the 28th and misses it by up to 0.4 s when it is not. The sort after
the upload takes 117 to 159 ms against 108 ms on the 28th, the same
recompute on a busier machine.

Process memory, MiB, working set (private commit):

| Point | Retained, 28th | Retained, this series | Released, 28th | Released, this series |
| --- | ---: | ---: | ---: | ---: |
| Records built in Dart | 361 | 361 to 362 | 360 | 361 to 362 |
| After upload | 632 | 630 to 642 | 632 | 627 to 631 |
| After the settle step | 619 (662) | 648 to 662 (692 to 707) | 387 (430) | 382 to 390 (425 to 432) |

Released memory is unchanged. Retained memory after the settle step is 30 to
40 MiB above the single run of the 28th; the ID hash index accounts for
8 MiB of it, and the rest was not attributed in this series (the same figure
appeared with a two-pass packer and with a string index, so it is not the
packing buffers; the 28th's single run is the other candidate). At 100,000
records (2 slices) the open took 434 ms against 434 ms on the 28th, with the
build at 168 ms against 103 ms, the same busier machine.

## What remains on this path

Native parse on the calling thread is now the largest per-slice stage, 33 to
60 ms for about 77,000 records of three cells, most of it the allocation of
230,000 strings; a dataset that stored cells in one arena would remove it
and is the typed-cell protocol change the roadmap defers. The packing in
Dart, 24 to 34 ms per slice, is a loop over code units and is hidden behind
the previous slice's apply except for the first slice. The ID index costs
eight bytes per record and one merge pass per slice.

## Limits

One machine on one busier day, three runs per mode; no comparison with
another framework and no presentation measurement. The open includes the
slices because the tool awaits them; an application has its window after
the first frame, before any slice. The retained-mode memory difference
against the 28th is bounded but not attributed.
