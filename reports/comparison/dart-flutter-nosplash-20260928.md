# Dart AOT and Flutter Windows with splash-free buttons: three foreground repetitions

Rendered from [dart-flutter-nosplash-20260928-summary.json](dart-flutter-nosplash-20260928-summary.json): 3 rotated repetitions of each workload in Dart AOT, Flutter Windows. Each cell is the median across completed runs with the [min, max] range; memory is the per-run p50 of 250 ms process samples, and CPU is process time over the measured interval with one logical core as 100 percent.

## Reliability

| Workload | Implementation | Attempts | Completed | Correctness failures | Equal-work eligible | Driver deadline misses per run |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | 5 | 3 | 0 | 3 | 0, 0, 0 |
| idle | Flutter Windows | 3 | 3 | 0 | 3 | 0, 0, 0 |
| scroll | Dart AOT | 3 | 3 | 0 | 2 | 0, 0, 2 |
| scroll | Flutter Windows | 3 | 3 | 0 | 0 | 1, 1, 1 |
| cell | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| cell | Flutter Windows | 3 | 3 | 0 | 3 | 0, 0, 0 |
| burst | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| burst | Flutter Windows | 3 | 3 | 0 | 3 | 0, 0, 0 |

## Memory, MiB

| Workload | Implementation | Working set median [min, max] | Private bytes median [min, max] |
| --- | --- | ---: | ---: |
| idle | Dart AOT | 137.98 [137.97, 138.02] | 151.54 [151.38, 151.83] |
| idle | Flutter Windows | 172.91 [172.64, 173.04] | 178.77 [178.41, 178.89] |
| scroll | Dart AOT | 145.18 [139.12, 145.25] | 158.59 [152.59, 158.69] |
| scroll | Flutter Windows | 181.29 [180.73, 183.53] | 188.23 [188.14, 191.12] |
| cell | Dart AOT | 138.82 [138.72, 139.16] | 153.44 [152.91, 154.07] |
| cell | Flutter Windows | 176.72 [176.27, 176.88] | 183.75 [183.65, 184.67] |
| burst | Dart AOT | 148.03 [147.98, 148.11] | 162.07 [161.77, 163.34] |
| burst | Flutter Windows | 181.71 [180.57, 185.11] | 188.84 [187.48, 192.83] |

## CPU, percent of one logical core

| Workload | Implementation | CPU median [min, max] |
| --- | --- | ---: |
| idle | Dart AOT | 0.8 [0.6, 0.9] |
| idle | Flutter Windows | 0.8 [0.5, 1.1] |
| scroll | Dart AOT | 20.9 [19.4, 22.2] |
| scroll | Flutter Windows | 21.1 [20.2, 25.5] |
| cell | Dart AOT | 2.3 [2.2, 2.5] |
| cell | Flutter Windows | 4.7 [3.4, 4.7] |
| burst | Dart AOT | 17.2 [15.2, 18.0] |
| burst | Flutter Windows | 17.8 [16.1, 18.9] |

## Window availability, ms from process launch to a discovered HWND

| Implementation | Median [min, max] over every workload run |
| --- | ---: |
| Dart AOT | 459 [330, 786] |
| Flutter Windows | 64 [46, 93] |

## Application frame histograms, per run

Each row is one run's own cumulative histogram since window creation, including startup and warmup; percentiles are not pooled across runs and the estimators differ between fixtures.

| Workload | Implementation | Run | Samples | p50 us | p95 us | p99 us | Max us | Source |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | dart-flutter-nosplash-20260928-0-retry2 | 3 | 5648.383 | 9723.903 | 9723.903 | - | native draw |
| idle | Dart AOT | dart-flutter-nosplash-20260928-1 | 3 | 2867.199 | 7782.399 | 7782.399 | - | native draw |
| idle | Dart AOT | dart-flutter-nosplash-20260928-2 | 3 | 3172.351 | 7917.567 | 7917.567 | - | native draw |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-0 | 29 | 279 | 716 | 777 | 777 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-0 | 29 | 1401 | 2992 | 33103 | 33103 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-0 | 29 | 2612 | 14238 | 77340 | 77340 | FrameTiming total |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-1 | 14 | 323 | 585 | 585 | 585 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-1 | 14 | 1470 | 30951 | 30951 | 30951 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-1 | 14 | 2803 | 75342 | 75342 | 75342 | FrameTiming total |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-2 | 14 | 330 | 853 | 853 | 853 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-2 | 14 | 1749 | 23454 | 23454 | 23454 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-2 | 14 | 3090 | 74181 | 74181 | 74181 | FrameTiming total |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-0 | 595 | 2672.639 | 3827.711 | 4427.775 | - | native draw |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-1 | 603 | 2605.055 | 3780.607 | 4296.703 | - | native draw |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-2 | 603 | 2418.687 | 3364.863 | 3813.375 | - | native draw |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-0 | 570 | 746 | 1241 | 1638 | 2159 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-0 | 570 | 1219 | 1927 | 2390 | 24583 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-0 | 570 | 3195 | 4504 | 5264 | 60075 | FrameTiming total |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-1 | 621 | 830 | 1270 | 1629 | 1845 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-1 | 621 | 1396 | 1853 | 2527 | 30436 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-1 | 621 | 3447 | 4546 | 5269 | 93864 | FrameTiming total |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-2 | 619 | 967 | 1427 | 1863 | 2849 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-2 | 619 | 1573 | 2170 | 2467 | 28544 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-2 | 619 | 3763 | 5040 | 5693 | 76262 | FrameTiming total |
| cell | Dart AOT | dart-flutter-nosplash-20260928-0 | 56 | 1825.791 | 3225.599 | 7708.671 | - | native draw |
| cell | Dart AOT | dart-flutter-nosplash-20260928-1 | 56 | 2299.903 | 4028.415 | 8421.375 | - | native draw |
| cell | Dart AOT | dart-flutter-nosplash-20260928-2 | 55 | 2201.599 | 3248.127 | 7053.311 | - | native draw |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-0 | 96 | 772 | 1475 | 1806 | 1806 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-0 | 96 | 1545 | 2435 | 35152 | 35152 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-0 | 96 | 3376 | 5144 | 74321 | 74321 | FrameTiming total |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-1 | 76 | 1049 | 1672 | 1864 | 1864 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-1 | 76 | 1806 | 3202 | 36453 | 36453 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-1 | 76 | 3979 | 5429 | 110769 | 110769 | FrameTiming total |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-2 | 76 | 1052 | 1696 | 2142 | 2142 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-2 | 76 | 1719 | 2716 | 29842 | 29842 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-2 | 76 | 3786 | 5324 | 76503 | 76503 | FrameTiming total |
| burst | Dart AOT | dart-flutter-nosplash-20260928-0 | 354 | 2330.623 | 3405.823 | 3704.831 | - | native draw |
| burst | Dart AOT | dart-flutter-nosplash-20260928-1 | 364 | 2279.423 | 3201.023 | 3964.927 | - | native draw |
| burst | Dart AOT | dart-flutter-nosplash-20260928-2 | 306 | 2633.727 | 3667.967 | 4325.375 | - | native draw |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-0 | 324 | 1396 | 2187 | 2400 | 2496 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-0 | 324 | 1669 | 2640 | 3726 | 79983 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-0 | 324 | 4183 | 5807 | 6689 | 142097 | FrameTiming total |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-1 | 325 | 1537 | 2375 | 3242 | 8296 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-1 | 325 | 1843 | 2787 | 3903 | 42646 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-1 | 325 | 4461 | 6643 | 11135 | 106894 | FrameTiming total |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-2 | 358 | 1413 | 2263 | 2591 | 3300 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-2 | 358 | 1750 | 2811 | 4362 | 41613 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-2 | 358 | 4109 | 6342 | 7470 | 108680 | FrameTiming total |

## Application work, per run

| Workload | Implementation | Run | Updates | Cells written | Rows or cells built |
| --- | --- | --- | ---: | ---: | ---: |
| idle | Dart AOT | dart-flutter-nosplash-20260928-0-retry2 | 0 | 0 |  |
| idle | Dart AOT | dart-flutter-nosplash-20260928-1 | 0 | 0 |  |
| idle | Dart AOT | dart-flutter-nosplash-20260928-2 | 0 | 0 |  |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-0 | 0 | 0 | 18 |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-1 | 0 | 0 | 18 |
| idle | Flutter Windows | dart-flutter-nosplash-20260928-2 | 0 | 0 | 18 |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-0 | 0 | 0 |  |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-1 | 0 | 0 |  |
| scroll | Dart AOT | dart-flutter-nosplash-20260928-2 | 0 | 0 |  |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-0 | 0 | 0 | 1478 |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-1 | 0 | 0 | 1478 |
| scroll | Flutter Windows | dart-flutter-nosplash-20260928-2 | 0 | 0 | 1478 |
| cell | Dart AOT | dart-flutter-nosplash-20260928-0 | 50 | 50 |  |
| cell | Dart AOT | dart-flutter-nosplash-20260928-1 | 50 | 50 |  |
| cell | Dart AOT | dart-flutter-nosplash-20260928-2 | 50 | 50 |  |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-0 | 50 | 50 | 918 |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-1 | 50 | 50 | 918 |
| cell | Flutter Windows | dart-flutter-nosplash-20260928-2 | 50 | 50 | 918 |
| burst | Dart AOT | dart-flutter-nosplash-20260928-0 | 300 | 2400 |  |
| burst | Dart AOT | dart-flutter-nosplash-20260928-1 | 300 | 2400 |  |
| burst | Dart AOT | dart-flutter-nosplash-20260928-2 | 300 | 2400 |  |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-0 | 300 | 2400 | 5400 |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-1 | 300 | 2400 | 5400 |
| burst | Flutter Windows | dart-flutter-nosplash-20260928-2 | 300 | 2400 | 5418 |

