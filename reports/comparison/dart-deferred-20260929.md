# Dart AOT with deferred datasets: three foreground repetitions

Rendered from [dart-deferred-20260929-summary.json](dart-deferred-20260929-summary.json): 3 rotated repetitions of each workload in Dart AOT. Each cell is the median across completed runs with the [min, max] range; memory is the per-run p50 of 250 ms process samples, and CPU is process time over the measured interval with one logical core as 100 percent.

## Reliability

| Workload | Implementation | Attempts | Completed | Correctness failures | Equal-work eligible | Driver deadline misses per run |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| scroll | Dart AOT | 3 | 3 | 0 | 0 | 6, 2, 2 |
| cell | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| burst | Dart AOT | 3 | 3 | 0 | 2 | 1, 0, 0 |

## Memory, MiB

| Workload | Implementation | Working set median [min, max] | Private bytes median [min, max] |
| --- | --- | ---: | ---: |
| idle | Dart AOT | 151.86 [141.40, 152.09] | 156.61 [154.78, 156.99] |
| scroll | Dart AOT | 148.62 [148.61, 148.84] | 162.36 [162.13, 162.48] |
| cell | Dart AOT | 142.36 [142.27, 142.50] | 157.14 [156.67, 157.78] |
| burst | Dart AOT | 166.83 [166.62, 167.02] | 180.68 [180.55, 180.95] |

## CPU, percent of one logical core

| Workload | Implementation | CPU median [min, max] |
| --- | --- | ---: |
| idle | Dart AOT | 1.1 [0.6, 1.4] |
| scroll | Dart AOT | 27.2 [18.0, 28.1] |
| cell | Dart AOT | 3.1 [2.5, 4.8] |
| burst | Dart AOT | 15.0 [12.2, 15.6] |

## Window availability, ms from process launch to a discovered HWND

| Implementation | Median [min, max] over every workload run |
| --- | ---: |
| Dart AOT | 255 [185, 419] |

## Application frame histograms, per run

Each row is one run's own cumulative histogram since window creation, including startup and warmup; percentiles are not pooled across runs and the estimators differ between fixtures.

| Workload | Implementation | Run | Samples | p50 us | p95 us | p99 us | Max us | Source |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | dart-deferred-20260929-0 | 8 | 1994.751 | 7614.463 | 7614.463 | - | native draw |
| idle | Dart AOT | dart-deferred-20260929-1 | 5 | 1544.191 | 5562.367 | 5562.367 | - | native draw |
| idle | Dart AOT | dart-deferred-20260929-2 | 3 | 5189.631 | 7311.359 | 7311.359 | - | native draw |
| scroll | Dart AOT | dart-deferred-20260929-0 | 575 | 3391.487 | 4866.047 | 5308.415 | - | native draw |
| scroll | Dart AOT | dart-deferred-20260929-1 | 605 | 3436.543 | 4734.975 | 5357.567 | - | native draw |
| scroll | Dart AOT | dart-deferred-20260929-2 | 602 | 2075.647 | 3041.279 | 3874.815 | - | native draw |
| cell | Dart AOT | dart-deferred-20260929-0 | 57 | 2619.391 | 4378.623 | 9641.983 | - | native draw |
| cell | Dart AOT | dart-deferred-20260929-1 | 59 | 1929.215 | 3661.823 | 8404.991 | - | native draw |
| cell | Dart AOT | dart-deferred-20260929-2 | 59 | 1662.975 | 3387.391 | 5570.559 | - | native draw |
| burst | Dart AOT | dart-deferred-20260929-0 | 302 | 2584.575 | 4325.375 | 5083.135 | - | native draw |
| burst | Dart AOT | dart-deferred-20260929-1 | 305 | 2394.111 | 3784.703 | 4077.567 | - | native draw |
| burst | Dart AOT | dart-deferred-20260929-2 | 343 | 1646.591 | 2150.399 | 2809.855 | - | native draw |

## Application work, per run

| Workload | Implementation | Run | Updates | Cells written | Rows or cells built |
| --- | --- | --- | ---: | ---: | ---: |
| idle | Dart AOT | dart-deferred-20260929-0 | 0 | 0 |  |
| idle | Dart AOT | dart-deferred-20260929-1 | 0 | 0 |  |
| idle | Dart AOT | dart-deferred-20260929-2 | 0 | 0 |  |
| scroll | Dart AOT | dart-deferred-20260929-0 | 0 | 0 |  |
| scroll | Dart AOT | dart-deferred-20260929-1 | 0 | 0 |  |
| scroll | Dart AOT | dart-deferred-20260929-2 | 0 | 0 |  |
| cell | Dart AOT | dart-deferred-20260929-0 | 50 | 50 |  |
| cell | Dart AOT | dart-deferred-20260929-1 | 50 | 50 |  |
| cell | Dart AOT | dart-deferred-20260929-2 | 50 | 50 |  |
| burst | Dart AOT | dart-deferred-20260929-0 | 299 | 2392 |  |
| burst | Dart AOT | dart-deferred-20260929-1 | 300 | 2400 |  |
| burst | Dart AOT | dart-deferred-20260929-2 | 300 | 2400 |  |

