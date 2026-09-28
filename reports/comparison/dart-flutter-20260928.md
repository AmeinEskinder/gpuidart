# Dart AOT and Flutter Windows with stock Material buttons: three foreground repetitions

Rendered from [dart-flutter-20260928-summary.json](dart-flutter-20260928-summary.json): 3 rotated repetitions of each workload in Dart AOT, Flutter Windows. Each cell is the median across completed runs with the [min, max] range; memory is the per-run p50 of 250 ms process samples, and CPU is process time over the measured interval with one logical core as 100 percent.

## Reliability

| Workload | Implementation | Attempts | Completed | Correctness failures | Equal-work eligible | Driver deadline misses per run |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | 5 | 3 | 0 | 3 | 0, 0, 0 |
| idle | Flutter Windows | 3 | 3 | 0 | 3 | 0, 0, 0 |
| scroll | Dart AOT | 3 | 3 | 1 | 1 | 0, 2, 3 |
| scroll | Flutter Windows | 3 | 3 | 0 | 1 | 1, 2, 0 |
| cell | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| cell | Flutter Windows | 3 | 3 | 0 | 3 | 0, 0, 0 |
| burst | Dart AOT | 3 | 3 | 0 | 3 | 0, 0, 0 |
| burst | Flutter Windows | 3 | 3 | 0 | 2 | 0, 1, 0 |

## Memory, MiB

| Workload | Implementation | Working set median [min, max] | Private bytes median [min, max] |
| --- | --- | ---: | ---: |
| idle | Dart AOT | 138.07 [138.01, 138.52] | 151.79 [151.43, 151.91] |
| idle | Flutter Windows | 173.38 [173.22, 174.06] | 179.20 [178.98, 179.91] |
| scroll | Dart AOT | 145.46 [145.09, 145.56] | 158.93 [158.36, 158.95] |
| scroll | Flutter Windows | 183.21 [180.22, 184.82] | 190.61 [188.07, 192.81] |
| cell | Dart AOT | 138.87 [138.80, 138.94] | 153.19 [153.00, 154.54] |
| cell | Flutter Windows | 179.69 [179.26, 181.08] | 187.26 [186.55, 188.77] |
| burst | Dart AOT | 148.04 [147.89, 148.11] | 162.44 [162.07, 162.91] |
| burst | Flutter Windows | 190.88 [182.47, 199.64] | 190.41 [189.07, 200.19] |

## CPU, percent of one logical core

| Workload | Implementation | CPU median [min, max] |
| --- | --- | ---: |
| idle | Dart AOT | 0.6 [0.6, 1.2] |
| idle | Flutter Windows | 0.5 [0.2, 0.8] |
| scroll | Dart AOT | 21.4 [18.6, 27.7] |
| scroll | Flutter Windows | 23.0 [23.0, 23.6] |
| cell | Dart AOT | 3.0 [2.7, 3.0] |
| cell | Flutter Windows | 19.4 [18.7, 19.5] |
| burst | Dart AOT | 15.8 [14.8, 19.4] |
| burst | Flutter Windows | 29.5 [25.5, 37.2] |

## Window availability, ms from process launch to a discovered HWND

| Implementation | Median [min, max] over every workload run |
| --- | ---: |
| Dart AOT | 477 [347, 645] |
| Flutter Windows | 65 [44, 82] |

## Application frame histograms, per run

Each row is one run's own cumulative histogram since window creation, including startup and warmup; percentiles are not pooled across runs and the estimators differ between fixtures.

| Workload | Implementation | Run | Samples | p50 us | p95 us | p99 us | Max us | Source |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| idle | Dart AOT | dart-flutter-20260928-0-retry2 | 22 | 2334.719 | 5111.807 | 10969.087 | - | native draw |
| idle | Dart AOT | dart-flutter-20260928-1 | 2 | 4239.359 | 11722.751 | 11722.751 | - | native draw |
| idle | Dart AOT | dart-flutter-20260928-2 | 2 | 3174.399 | 8478.719 | 8478.719 | - | native draw |
| idle | Flutter Windows | dart-flutter-20260928-0 | 15 | 357 | 1001 | 1001 | 1001 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-20260928-0 | 15 | 1883 | 29142 | 29142 | 29142 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-20260928-0 | 15 | 3458 | 92963 | 92963 | 92963 | FrameTiming total |
| idle | Flutter Windows | dart-flutter-20260928-1 | 14 | 339 | 797 | 797 | 797 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-20260928-1 | 14 | 1641 | 28838 | 28838 | 28838 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-20260928-1 | 14 | 3019 | 59643 | 59643 | 59643 | FrameTiming total |
| idle | Flutter Windows | dart-flutter-20260928-2 | 15 | 331 | 687 | 687 | 687 | FrameTiming build |
| idle | Flutter Windows | dart-flutter-20260928-2 | 15 | 1614 | 17953 | 17953 | 17953 | FrameTiming raster |
| idle | Flutter Windows | dart-flutter-20260928-2 | 15 | 3166 | 58778 | 58778 | 58778 | FrameTiming total |
| scroll | Dart AOT | dart-flutter-20260928-0 | 574 | 2439.167 | 3526.655 | 3880.959 | - | native draw |
| scroll | Dart AOT | dart-flutter-20260928-1 | 605 | 2641.919 | 3977.215 | 4374.527 | - | native draw |
| scroll | Dart AOT | dart-flutter-20260928-2 | 561 | 3203.071 | 4763.647 | 5283.839 | - | native draw |
| scroll | Flutter Windows | dart-flutter-20260928-0 | 619 | 917 | 1435 | 1792 | 10685 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-20260928-0 | 619 | 1459 | 2100 | 2373 | 27714 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-20260928-0 | 619 | 3699 | 5144 | 5669 | 59936 | FrameTiming total |
| scroll | Flutter Windows | dart-flutter-20260928-1 | 597 | 901 | 1557 | 1951 | 2718 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-20260928-1 | 597 | 1499 | 2184 | 3011 | 30275 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-20260928-1 | 597 | 3563 | 4928 | 6153 | 65329 | FrameTiming total |
| scroll | Flutter Windows | dart-flutter-20260928-2 | 620 | 828 | 1265 | 1570 | 1834 | FrameTiming build |
| scroll | Flutter Windows | dart-flutter-20260928-2 | 620 | 1357 | 2098 | 2475 | 20972 | FrameTiming raster |
| scroll | Flutter Windows | dart-flutter-20260928-2 | 620 | 3483 | 4917 | 5557 | 47958 | FrameTiming total |
| cell | Dart AOT | dart-flutter-20260928-0 | 58 | 1735.679 | 3233.791 | 8544.255 | - | native draw |
| cell | Dart AOT | dart-flutter-20260928-1 | 64 | 2764.799 | 3950.591 | 8228.863 | - | native draw |
| cell | Dart AOT | dart-flutter-20260928-2 | 57 | 1986.559 | 3284.991 | 9207.807 | - | native draw |
| cell | Flutter Windows | dart-flutter-20260928-0 | 631 | 342 | 1120 | 1473 | 2521 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-20260928-0 | 631 | 1731 | 2396 | 2880 | 23890 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-20260928-0 | 631 | 3240 | 4537 | 5077 | 65685 | FrameTiming total |
| cell | Flutter Windows | dart-flutter-20260928-1 | 625 | 306 | 988 | 1362 | 1771 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-20260928-1 | 625 | 1459 | 2345 | 2871 | 23425 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-20260928-1 | 625 | 3060 | 4420 | 5096 | 59271 | FrameTiming total |
| cell | Flutter Windows | dart-flutter-20260928-2 | 636 | 292 | 874 | 1042 | 1238 | FrameTiming build |
| cell | Flutter Windows | dart-flutter-20260928-2 | 636 | 1400 | 1995 | 2357 | 34595 | FrameTiming raster |
| cell | Flutter Windows | dart-flutter-20260928-2 | 636 | 2867 | 4170 | 4831 | 78208 | FrameTiming total |
| burst | Dart AOT | dart-flutter-20260928-0 | 308 | 2254.847 | 3080.191 | 3287.039 | - | native draw |
| burst | Dart AOT | dart-flutter-20260928-1 | 360 | 2691.071 | 3770.367 | 4321.279 | - | native draw |
| burst | Dart AOT | dart-flutter-20260928-2 | 304 | 2215.935 | 3184.639 | 3446.783 | - | native draw |
| burst | Flutter Windows | dart-flutter-20260928-0 | 626 | 732 | 1973 | 2592 | 3153 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-20260928-0 | 626 | 1851 | 2739 | 3445 | 27120 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-20260928-0 | 626 | 4035 | 5429 | 6525 | 93669 | FrameTiming total |
| burst | Flutter Windows | dart-flutter-20260928-1 | 628 | 908 | 2868 | 3451 | 4293 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-20260928-1 | 628 | 2259 | 3522 | 4585 | 33452 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-20260928-1 | 628 | 4735 | 7226 | 8732 | 93006 | FrameTiming total |
| burst | Flutter Windows | dart-flutter-20260928-2 | 631 | 589 | 1765 | 2200 | 2659 | FrameTiming build |
| burst | Flutter Windows | dart-flutter-20260928-2 | 631 | 1620 | 2446 | 3036 | 18057 | FrameTiming raster |
| burst | Flutter Windows | dart-flutter-20260928-2 | 631 | 3542 | 5305 | 6173 | 62349 | FrameTiming total |

## Application work, per run

| Workload | Implementation | Run | Updates | Cells written | Rows or cells built |
| --- | --- | --- | ---: | ---: | ---: |
| idle | Dart AOT | dart-flutter-20260928-0-retry2 | 0 | 0 |  |
| idle | Dart AOT | dart-flutter-20260928-1 | 0 | 0 |  |
| idle | Dart AOT | dart-flutter-20260928-2 | 0 | 0 |  |
| idle | Flutter Windows | dart-flutter-20260928-0 | 0 | 0 | 18 |
| idle | Flutter Windows | dart-flutter-20260928-1 | 0 | 0 | 18 |
| idle | Flutter Windows | dart-flutter-20260928-2 | 0 | 0 | 18 |
| scroll | Dart AOT | dart-flutter-20260928-0 | 0 | 0 |  |
| scroll | Dart AOT | dart-flutter-20260928-1 | 0 | 0 |  |
| scroll | Dart AOT | dart-flutter-20260928-2 | 0 | 0 |  |
| scroll | Flutter Windows | dart-flutter-20260928-0 | 0 | 0 | 1478 |
| scroll | Flutter Windows | dart-flutter-20260928-1 | 0 | 0 | 1476 |
| scroll | Flutter Windows | dart-flutter-20260928-2 | 0 | 0 | 1481 |
| cell | Dart AOT | dart-flutter-20260928-0 | 50 | 50 |  |
| cell | Dart AOT | dart-flutter-20260928-1 | 50 | 50 |  |
| cell | Dart AOT | dart-flutter-20260928-2 | 50 | 50 |  |
| cell | Flutter Windows | dart-flutter-20260928-0 | 50 | 50 | 918 |
| cell | Flutter Windows | dart-flutter-20260928-1 | 50 | 50 | 918 |
| cell | Flutter Windows | dart-flutter-20260928-2 | 50 | 50 | 918 |
| burst | Dart AOT | dart-flutter-20260928-0 | 300 | 2400 |  |
| burst | Dart AOT | dart-flutter-20260928-1 | 300 | 2400 |  |
| burst | Dart AOT | dart-flutter-20260928-2 | 300 | 2400 |  |
| burst | Flutter Windows | dart-flutter-20260928-0 | 300 | 2400 | 5400 |
| burst | Flutter Windows | dart-flutter-20260928-1 | 299 | 2392 | 5400 |
| burst | Flutter Windows | dart-flutter-20260928-2 | 300 | 2400 | 5418 |

