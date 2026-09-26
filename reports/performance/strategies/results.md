# Recorded strategy results

Source `cbe8595`, release experiment binaries. Three normal repetitions per case; one separate allocation-profile repetition. Summaries preserve per-run samples and medians. All times below are microseconds, except where stated. These are hosted-machine results, not cross-platform rankings.

## 2,048-property AOT updates

Dart preparation is build + describe + diff + encoding, summed per update before summarizing. Native preparation is decode + staging + validation + application. The tables retain the separate metrics in linked JSON summaries. Framing/write and diagnostic reply time are excluded here.

| Platform | Operation | Strategy | Bytes | Dart prepare, us | Native prepare, us |
| --- | --- | --- | ---: | ---: | ---: |
| windows | unchanged | snapshot | 275,266.0 | 3,039.0 | 3,325.0 |
| windows | unchanged | subviews | 114.0 | 7.0 | 640.5 |
| windows | unchanged | patches | 78.0 | 3,485.0 | 1,314.0 |
| windows | property | snapshot | 275,269.0 | 2,688.5 | 3,600.0 |
| windows | property | subviews | 4,269.0 | 66.5 | 636.0 |
| windows | property | patches | 143.0 | 2,904.0 | 1,269.0 |
| windows | reorder | snapshot | 275,269.0 | 2,662.0 | 3,334.0 |
| windows | reorder | subviews | 970.0 | 34.5 | 683.5 |
| windows | reorder | patches | 3,779.5 | 2,697.0 | 1,188.0 |
| windows | insert | snapshot | 275,638.0 | 2,723.5 | 3,369.0 |
| windows | insert | subviews | 198.0 | 9.5 | 580.5 |
| windows | insert | patches | 212.0 | 2,668.5 | 1,121.0 |
| windows | remove | snapshot | 275,556.0 | 2,682.5 | 3,404.5 |
| windows | remove | subviews | 126.0 | 11.5 | 567.5 |
| windows | remove | patches | 111.0 | 2,695.0 | 1,165.5 |
| linux | unchanged | snapshot | 275,266.0 | 6,104.0 | 4,456.5 |
| linux | unchanged | subviews | 114.0 | 10.0 | 1,154.5 |
| linux | unchanged | patches | 78.0 | 7,485.5 | 2,046.5 |
| linux | property | snapshot | 275,269.0 | 4,690.5 | 4,094.5 |
| linux | property | subviews | 4,269.0 | 133.0 | 1,175.0 |
| linux | property | patches | 143.0 | 4,913.5 | 1,930.5 |
| linux | reorder | snapshot | 275,269.0 | 4,699.0 | 4,052.5 |
| linux | reorder | subviews | 970.0 | 50.0 | 1,118.5 |
| linux | reorder | patches | 3,779.5 | 4,923.5 | 2,067.0 |
| linux | insert | snapshot | 275,638.0 | 4,712.0 | 4,525.0 |
| linux | insert | subviews | 198.0 | 14.5 | 1,132.0 |
| linux | insert | patches | 212.0 | 4,794.5 | 2,296.5 |
| linux | remove | snapshot | 275,556.0 | 4,729.0 | 4,073.0 |
| linux | remove | subviews | 126.0 | 23.0 | 1,365.5 |
| linux | remove | patches | 111.0 | 4,806.5 | 2,115.0 |
| macos | unchanged | snapshot | 275,266.0 | 3,889.5 | 2,116.5 |
| macos | unchanged | subviews | 114.0 | 6.5 | 396.5 |
| macos | unchanged | patches | 78.0 | 4,468.0 | 797.5 |
| macos | property | snapshot | 275,269.0 | 3,975.5 | 2,062.0 |
| macos | property | subviews | 4,269.0 | 78.0 | 427.5 |
| macos | property | patches | 143.0 | 4,223.5 | 780.0 |
| macos | reorder | snapshot | 275,269.0 | 3,938.0 | 2,071.5 |
| macos | reorder | subviews | 970.0 | 38.0 | 435.5 |
| macos | reorder | patches | 3,779.5 | 4,179.5 | 818.5 |
| macos | insert | snapshot | 275,638.0 | 3,969.5 | 2,152.5 |
| macos | insert | subviews | 198.0 | 9.0 | 413.0 |
| macos | insert | patches | 212.0 | 4,051.5 | 787.5 |
| macos | remove | snapshot | 275,556.0 | 3,978.5 | 2,139.0 |
| macos | remove | subviews | 126.0 | 15.0 | 405.5 |
| macos | remove | patches | 111.0 | 4,194.5 | 761.0 |

## CPU render stages: property edit / full section reorder

Each cell is property / reorder. Layout gap includes surrounding GPUI work between request-layout and prepaint; these columns are not GPU or presentation timings.

| Platform | Strategy | Request layout, us | Layout gap, us | Prepaint, us | Paint, us |
| --- | --- | ---: | ---: | ---: | ---: |
| windows | snapshot | 7,958.0 / 7,545.0 | 6,158.0 / 5,953.0 | 2,378.5 / 2,257.0 | 2,337.5 / 2,269.0 |
| windows | subviews | 31.5 / 45.5 | 63.0 / 86.0 | 784.0 / 12,133.0 | 147.0 / 2,766.0 |
| windows | patches | 7,513.5 / 7,204.5 | 5,949.5 / 5,610.0 | 2,139.0 / 2,135.5 | 2,283.5 / 2,295.5 |
| linux | snapshot | 7,853.5 / 7,848.0 | 6,722.5 / 6,729.5 | 2,625.0 / 2,522.5 | 2,624.5 / 2,621.5 |
| linux | subviews | 55.0 / 50.0 | 78.0 / 77.0 | 1,114.5 / 15,300.5 | 236.0 / 2,893.5 |
| linux | patches | 7,419.5 / 7,478.5 | 6,757.0 / 6,723.0 | 2,579.5 / 2,495.5 | 2,600.5 / 2,598.5 |
| macos | snapshot | 4,200.5 / 4,425.5 | 4,746.5 / 4,582.0 | 1,748.0 / 1,692.0 | 1,786.0 / 1,801.0 |
| macos | subviews | 30.0 / 32.5 | 54.5 / 60.5 | 677.5 / 9,549.0 | 136.5 / 1,932.5 |
| macos | patches | 4,385.0 / 4,497.0 | 4,736.5 / 4,480.5 | 1,735.5 / 1,649.0 | 1,823.5 / 1,768.0 |

## Memory after the 40-update workload

MiB, normal-build AOT medians. Driver RSS includes the dataset/description mirror and accumulated evidence. Native memory includes duplicate experimental model/render descriptions and the shared fixture dataset copies. These are separate processes; RSS sums would double-count shared pages.

| Platform | Strategy | Driver RSS | Native RSS / working set | Native second metric | Native process peak |
| --- | --- | ---: | ---: | ---: | ---: |
| windows | snapshot | 50.87 | 94.32 | 81.41 | 82.83 |
| windows | subviews | 49.62 | 92.60 | 79.77 | 80.45 |
| windows | patches | 49.35 | 94.03 | 81.15 | 82.24 |
| linux | snapshot | 45.56 | 229.66 | 207.25 | 229.63 |
| linux | subviews | 45.57 | 227.91 | 205.51 | 227.97 |
| linux | patches | 47.03 | 227.68 | 205.35 | 227.57 |
| macos | snapshot | 48.77 | 119.95 | 71.19 | 75.03 |
| macos | subviews | 48.66 | 112.34 | 77.36 | 77.80 |
| macos | patches | 48.84 | 119.59 | 73.14 | 76.67 |

Second metric: Windows private commit; Linux PSS; macOS physical footprint. Peak: Windows commit, Linux RSS, macOS footprint. Linux RSS and peak RSS come from different accounting interfaces and need not agree at the page level. Driver peak RSS is retained in raw summaries; on Linux it often already exceeds later samples before the workload.

## Rust allocation-profile build

One AOT run per strategy/size/platform, separate from timing. Requested MiB, not OS memory. Workload allocation total is cumulative requested bytes after minus before; includes rendering and diagnostic replies across all 40 updates. Peak is the process lifetime requested-byte high water, not total temporary allocation.

| Platform | Strategy | Live before | Live after | Lifetime peak | Allocated during workload |
| --- | --- | ---: | ---: | ---: | ---: |
| windows | snapshot | 43.55 | 43.83 | 46.40 | 1296.02 |
| windows | subviews | 38.38 | 42.60 | 44.58 | 1593.73 |
| windows | patches | 43.68 | 43.96 | 46.08 | 1211.04 |
| linux | snapshot | 45.41 | 45.71 | 49.08 | 1487.62 |
| linux | subviews | 45.55 | 45.98 | 47.97 | 1608.56 |
| linux | patches | 45.41 | 45.69 | 47.80 | 1402.76 |
| macos | snapshot | 43.17 | 43.64 | 46.70 | 1240.25 |
| macos | subviews | 43.31 | 43.90 | 45.90 | 1267.20 |
| macos | patches | 43.17 | 43.57 | 45.68 | 1225.50 |

The full size slopes (128/512/2048), JIT results, separate stage costs and per-run tails are in each platform's `timing-analysis.json` and `allocation-analysis.json`. Eight observations per operation make its run p95 the maximum; these samples cannot support population tail-latency claims.
